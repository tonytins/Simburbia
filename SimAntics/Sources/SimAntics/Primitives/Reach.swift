import TSOFiles

extension Primitives {
    /// Reaches for the stack object, or into one of its slots, picking up or putting down on the
    /// animation's event 0 (opcode 47).
    ///
    /// Ports FreeSO's `VMReach`. 1.1097.1.0 has 118 instructions: 40 in mode 0, 78 in mode 1.
    ///
    /// - **Mode 0** reaches for the stack object and takes it in hand. The height is that of the
    ///   slot the object is in, or 0 on the floor or in a Sim's hand.
    /// - **Mode 1** reaches for the stack object's slot whose number is in the argument the operand
    ///   names: with an empty hand it takes what's there, else it puts what it holds there if the
    ///   slot is empty. With no such slot it goes false.
    ///
    /// The animation follows the height: sitting, `a2o-sit-reach-table`; below 2,
    /// `a2o-reach-floorht`; below 4, `a2o-reach-seatht`; else `a2o-reach-tableht`. A slot's height
    /// is its standard height's offset (floor 0, low table 2.5, table and counter 4, sitting 7,
    /// end table 4), or its own offset for a non-standard slot, rounded half to even as .NET's
    /// `Math.Round` does, so a low table counts as 2. The first run starts the animation and waits;
    /// later ones act on event 0, drop each event, and wait, until the animation ends, then go
    /// true, whether or not the pickup worked, as in FreeSO.
    ///
    /// Where it differs: FreeSO fails with no stack object, or a slot number past its slots, as a
    /// .NET exception; Simburbia fails with an error for the routine. A height that isn't one of
    /// the nine standard ones is an error too, where FreeSO's lookup would fail. plumbob-engine
    /// (a The Sims 1 engine) can go false when a pickup is refused, and after one runs the
    /// target's `CT - Grab` or `CT - Put` tree, which 1.1097.1.0's objects also have; FreeSO runs
    /// neither, and neither does Simburbia yet. Mode 2, reaching to the mouth, which TSO doesn't
    /// use, is unsupported, as FreeSO leaves it.
    public enum Reach: Primitive {
        public static let name = "reach"
        public static let opcode: UInt8 = 47

        /// FreeSO's `VMReachOperand`.
        public struct Operand: PrimitiveOperand, Equatable {
            public var mode: UInt16
            public var grabOrDrop: UInt16
            /// The argument holding the slot's number, in mode 1.
            public var slotParameter: UInt16

            public init(mode: UInt16, grabOrDrop: UInt16 = 1, slotParameter: UInt16 = 0) {
                self.mode = mode
                self.grabOrDrop = grabOrDrop
                self.slotParameter = slotParameter
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                mode = reader.uint16()
                grabOrDrop = reader.uint16()
                slotParameter = reader.uint16()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    for value in [mode, grabOrDrop, slotParameter] { writer.uint16(value) }
                }
            }
        }

        /// The standard slot heights' offsets, from height 1 (`SLOT.HeightOffsets`).
        static let heightOffsets: [Float] = [0, 2.5, 4, 4, 0, 0, 7, 4, 0]

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let sim = frame.caller, sim.isAvatar else { throw .invalidCast("Reach's caller isn't a Sim") }
            guard let target = frame.stackObject else { throw .nullReference("Reach has no stack object") }
            var completedPickup = false
            let height: Int
            switch operand.mode {
            case 0:
                let container = target.container
                if container === sim { completedPickup = true }
                if let container, !container.isAvatar {
                    height = try slotHeight(of: container, slot: Int(target.containerSlot))
                } else {
                    height = 0
                }
            case 1:
                let number = try slotNumber(operand, in: frame)
                guard target.containerSlots.indices.contains(number) else { return .gotoFalse }
                height = try slotHeight(of: target, slot: number)
            default:
                throw .unsupported("Reach mode \(operand.mode) (to the mouth)")
            }

            let name = sim.container != nil ? "a2o-sit-reach-table"
                : height < 2 ? "a2o-reach-floorht" : height < 4 ? "a2o-reach-seatht" : "a2o-reach-tableht"
            guard let clip = try frame.vm.animationClip(named: name) else { return .gotoFalse }

            // Starting the reach, or progressing it?
            guard let current = sim.sim.animations.first, current.clip.key == clip.key || completedPickup else {
                sim.sim.animations = [AnimationState(clip: clip)]
                sim.sim.leftHandPose = 0
                sim.sim.rightHandPose = 0
                return .continueNextTick
            }
            if current.endReached {
                sim.sim.animations = []
                return .gotoTrue
            }
            guard let event = current.eventQueue.first else { return .continueNextTick }
            if event == 0 { try act(operand, sim: sim, target: target, in: frame) }
            sim.sim.animations[0].eventQueue.removeFirst()
            return .continueNextTick
        }

        /// The pickup or putting down, on event 0. Failing is not reported, as in FreeSO.
        private static func act(_ operand: Operand, sim: Entity, target: Entity, in frame: StackFrame) throws(SimAnticsError) {
            if operand.mode == 0 {
                if sim.slot(0) == nil { try sim.placeInSlot(target, slot: 0, cleanOld: true) }
                return
            }
            let number = try slotNumber(operand, in: frame)
            if let held = sim.slot(0) {
                if target.slot(number) == nil { try target.placeInSlot(held, slot: number, cleanOld: true) }
            } else if let item = target.slot(number) {
                try sim.placeInSlot(item, slot: 0, cleanOld: true)
            }
        }

        private static func slotNumber(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> Int {
            let index = Int(operand.slotParameter)
            guard index < frame.arguments.count else { throw .indexOutOfRange("parameter \(index)") }
            return Int(frame.arguments[index])
        }

        /// A container slot's height for choosing the animation, rounded half to even.
        static func slotHeight(of entity: Entity, slot number: Int) throws(SimAnticsError) -> Int {
            guard entity.containerSlots.indices.contains(number) else { throw .indexOutOfRange("slot \(number)") }
            let slot = entity.containerSlots[number]
            let offset: Float
            if slot.height == 5 {
                offset = slot.offset.z
            } else {
                let index = Int(slot.height) - 1
                guard heightOffsets.indices.contains(index) else { throw .indexOutOfRange("slot height \(slot.height)") }
                offset = heightOffsets[index]
            }
            guard offset.isFinite, abs(offset) < 1_000_000 else { throw .simantics("slot \(number)'s offset isn't a usable height") }
            return Int(offset.rounded(.toNearestOrEven))
        }
    }
}
