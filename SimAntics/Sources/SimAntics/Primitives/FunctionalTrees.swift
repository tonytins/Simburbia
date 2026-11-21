extension Primitives {
    /// The object functions that Run Functional Tree and Find Best Object For Function name: each
    /// function's entry point, and the object data that scores an object for it.
    enum ObjectFunction {
        /// By function number: prepare food, cook food, flat surface, dispose, eat, pick up from slot,
        /// wash dish, eating surface, sit, stand, serving surface, clean, gardening, wash hands, and
        /// repair.
        static let entryPoints: [Entity.EntryPointIndex] = [
            .prepareFood, .cookFood, .placeOnSurface, .dispose, .eat, .pickupFromSlot, .washDish, .eatingSurface,
            .sit, .stand, .servingSurface, .clean, .gardening, .washHands, .repair,
        ]

        /// The object data an object scores by for each function; `nil` where only distance counts.
        static let scores: [ObjectVariable?] = [
            .prepValue, .cookValue, .surfaceValue, .disposeValue, nil, nil, .washDishValue, .eatingSurfaceValue,
            nil, nil, .servingSurfaceValue, .dirtyLevel, .gardeningValue, .washHandsValue, .repairState,
        ]

        /// The least score an object must have for a function, where there is one: dirt to be worth
        /// cleaning, wear to be worth repairing, and a garden to be worth tending.
        static func threshold(_ variable: ObjectVariable) -> Int16? {
            switch variable {
            case .dirtyLevel: 800
            case .repairState: 600
            case .gardeningValue: 25
            default: nil
            }
        }

        static func entryPoint(_ function: UInt16) throws(SimAnticsError) -> Entity.EntryPointIndex {
            guard Int(function) < entryPoints.count else { throw .indexOutOfRange("object function \(function)") }
            return entryPoints[Int(function)]
        }

        /// The object's routine for a function, if it has one, and whether its condition lets
        /// `caller` use it. The condition runs to completion on a check thread for the caller, with
        /// the object as callee and stack object; a condition routine that doesn't exist allows it.
        static func action(_ entry: Entity.EntryPointIndex, of object: Entity, for caller: Entity) throws(SimAnticsError) -> UInt16? {
            guard let table = object.entryPoints, table.indices.contains(entry.rawValue) else { return nil }
            let point = table[entry.rawValue]
            guard point.actionFunction != 0 else { return nil }
            guard point.conditionFunction != 0,
                  let condition = try object.vm.routine(opcode: point.conditionFunction, codeOwner: object.object) else {
                return point.actionFunction
            }
            let frame = StackFrame(thread: caller.thread, routine: condition, caller: caller, callee: object, codeOwner: object.object)
            frame.stackObject = object
            frame.arguments = [0, 0, 0, 0]
            return VMThread.evaluateCheck(entity: caller, frame: frame) == .returnTrue ? point.actionFunction : nil
        }
    }

    /// Runs the stack object's routine for a function, as a subroutine (opcode 20).
    ///
    /// The function names an entry point (``ObjectFunction``). When the stack object has a routine
    /// there and its condition allows the caller, the routine is pushed with the stack object as
    /// callee and stack object, its own code, and zeroed arguments, and its result comes back as a
    /// subroutine's does. With no stack object, no routine, or a condition against it, it's false;
    /// so is function 65535, which a wedding cake uses. Flag 1, which would show the stack object's
    /// icon for the interaction, only matters to drawing. A function past the table fails, with an
    /// error for the routine.
    public enum RunFunctionalTree: Primitive {
        public static let name = "run_functional_tree"
        public static let opcode: UInt8 = 20

        public struct Operand: PrimitiveOperand, Equatable {
            public var function: UInt16
            public var flags: UInt8

            public init(function: UInt16, flags: UInt8 = 0) {
                self.function = function
                self.flags = flags
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                function = reader.uint16()
                flags = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(function)
                    writer.uint8(flags)
                }
            }
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            if operand.function == 65535 { return .gotoFalse }
            let entry = try ObjectFunction.entryPoint(operand.function)
            guard let object = frame.stackObject, !object.isDead else { return .gotoFalse }
            guard let caller = frame.caller else { throw .nullReference("Run Functional Tree has no caller") }
            guard let id = try ObjectFunction.action(entry, of: object, for: caller),
                  let routine = try frame.vm.routine(opcode: id, codeOwner: object.object) else { return .gotoFalse }
            let child = StackFrame(thread: frame.thread, routine: routine, caller: frame.caller, callee: object, codeOwner: object.object)
            child.stackObject = object
            child.isActionTree = frame.isActionTree
            child.arguments = [Int16](repeating: 0, count: Int(routine.argumentCount))
            frame.thread.push(child)
            return .continue
        }
    }

    /// Finds the best object on the lot for a function and makes it the stack object (opcode 14).
    ///
    /// Every object in the world, in object ID order, that isn't locked out or disabled, has a
    /// routine for the function's entry point whose condition allows the caller, and isn't in use
    /// (occupied, or any part of it the callee of a routine on a Sim's stack) is scored: its
    /// function's object data, where it has one and it meets the threshold, less a third of its
    /// distance from the caller (a level counting 30 tiles). The first with the highest score wins
    /// and it's true; with none, it's false. A function past the table fails, with an error for the
    /// routine.
    public enum FindBestObjectForFunction: Primitive {
        public static let name = "find_best_object_for_function"
        public static let opcode: UInt8 = 14

        public struct Operand: PrimitiveOperand, Equatable {
            public var function: UInt16

            public init(function: UInt16) { self.function = function }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                function = reader.uint16()
            }

            public func encoded() -> [UInt8] { OperandWriter.bytes { $0.uint16(function) } }
        }

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            let entry = try ObjectFunction.entryPoint(operand.function)
            let scoreVariable = ObjectFunction.scores[Int(operand.function)]
            guard let caller = frame.caller else { throw .nullReference("Find Best Object For Function has no caller") }
            var best: (score: Int, object: Entity)?
            for object in frame.vm.entities {
                if try object.value(of: ObjectVariable.lockoutCount.rawValue) > 0 || object.disabledFlags != 0
                    || object.position.isOutOfWorld { continue }
                guard try ObjectFunction.action(entry, of: object, for: caller) != nil, !object.isInUse else { continue }
                var score = 0
                if let scoreVariable {
                    let value = try object.value(of: scoreVariable.rawValue)
                    if let threshold = ObjectFunction.threshold(scoreVariable), value < threshold { continue }
                    score = Int(value)
                }
                let dx = Int(object.position.x) - Int(caller.position.x)
                let dy = Int(object.position.y) - Int(caller.position.y)
                let dLevel = Int(object.position.level) - Int(caller.position.level)
                score -= Int(Double(dx * dx + dy * dy + dLevel * dLevel * 900 * 256).squareRoot()) / 3
                if best.map({ score > $0.score }) ?? true { best = (score, object) }
            }
            guard let best else { return .gotoFalse }
            frame.stackObject = best.object
            return .gotoTrue
        }
    }
}
