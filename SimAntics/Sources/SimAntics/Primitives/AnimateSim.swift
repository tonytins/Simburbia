import TSOContent
import TSOFiles

extension Primitives {
    /// Plays an animation on the calling Sim (opcode 44).
    ///
    /// Ports FreeSO's `VMAnimateSim`, checked against plumbob-engine's (a The Sims 1 engine) and
    /// against how 1.1097.1.0's 13,886 Animate Sim instructions use it. The mode is the flags'
    /// bits 0 and 4 (`flags & 1 | flags >> 3 & 2`):
    ///
    /// - **0, play and wait** (13,174 instructions): the first run starts the animation, replacing
    ///   whatever was playing, and waits a tick. Later runs, while the same animation plays, hand
    ///   the routine its events: each `xevt` the animation fired goes into a local (flag 32) or
    ///   the first parameter, and the primitive goes false; once it has ended and no events are
    ///   left, it stops the animation and goes true. When it ends having run fewer events than
    ///   the operand expects, the missing ones are made up, numbered from the count run so far, so
    ///   the routine still hears them (FreeSO's "required for bath drain").
    /// - **3** (161): stops the carry animation, then plays and waits as 0 does.
    /// - **2, carry** (382): sets the carry animation and goes true.
    /// - **1** (169): goes true, as in FreeSO. plumbob-engine plays it as a background loop the
    ///   routine doesn't wait on, which only drawing would show; it waits for the client.
    ///
    /// An ID of 0 (752 instructions) stops everything and plays the walk animation for the Sim's
    /// posture (sitting 1, kneeling 2, else standing, the walk table's 3), looping, and sets the
    /// default carry animation if the Sim holds something in its hand, or clears it.
    ///
    /// The name comes from a string table chosen by the source (FreeSO's `VMMemory.GetAnimation`):
    /// the code owner's table (its `OBJD`'s animation table, else `STR#` 129); the stack object's,
    /// likewise; or the global's `STR#` 128 (global), 130 (person stock), or 156 (misc). With the ID
    /// from a parameter, the object source means the stack object, as FreeSO's fix for a roller
    /// coaster has it. A name with no animation, or a missing table, goes true without playing.
    ///
    /// Not yet: the hurry flag (8, 143 instructions), which lets an interaction interrupt the
    /// animation, waits for the interaction queue (phase D); flag 64 (276), which plumbob-engine
    /// reads as practice scaling, does nothing, as in FreeSO.
    public enum AnimateSim: Primitive {
        public static let name = "animate"
        public static let opcode: UInt8 = 44

        /// FreeSO's `VMAnimateSimOperand`; its second padding byte is written back as zero, as
        /// FreeSO writes it.
        public struct Operand: PrimitiveOperand, Equatable {
            public var animationID: UInt16
            /// The local the event goes into, with flag 32.
            public var localEventNumber: UInt8
            /// Where the animation comes from (`VMAnimationScope`): 0 object, 1 global, 2 person
            /// stock, 3 misc.
            public var source: UInt8
            public var flags: UInt8
            /// How many events below 100 the animation should run.
            public var expectedEventCount: UInt8

            public init(animationID: UInt16, localEventNumber: UInt8 = 0, source: UInt8 = 0, flags: UInt8 = 0,
                        expectedEventCount: UInt8 = 0) {
                self.animationID = animationID
                self.localEventNumber = localEventNumber
                self.source = source
                self.flags = flags
                self.expectedEventCount = expectedEventCount
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                animationID = reader.uint16()
                localEventNumber = reader.uint8()
                _ = reader.uint8()
                source = reader.uint8()
                flags = reader.uint8()
                expectedEventCount = reader.uint8()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint16(animationID)
                    writer.uint8(localEventNumber)
                    writer.uint8(0)
                    writer.uint8(source)
                    writer.uint8(flags)
                    writer.uint8(expectedEventCount)
                }
            }

            /// 0 play and wait, 1 background (ignored), 2 carry, 3 stop carry then play and wait.
            public var mode: UInt8 { flags & 1 | (flags >> 3) & 2 }
            public var playsBackwards: Bool { flags & 2 != 0 }
            public var idFromParameter: Bool { flags & 4 != 0 }
            public var storesEventInLocal: Bool { flags & 32 != 0 }
        }

        /// The default carry animation, for a Sim holding something when its animation resets.
        static let defaultCarry = "a2o-rarm-carry-loop"

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let sim = frame.caller, sim.isAvatar else { throw .invalidCast("Animate Sim's caller isn't a Sim") }
            var id = operand.animationID
            if operand.idFromParameter {
                let index = Int(operand.animationID)
                guard index < frame.arguments.count else { throw .indexOutOfRange("parameter \(index)") }
                id = UInt16(bitPattern: frame.arguments[index])
            }
            if id == 0 { return try reset(sim, backwards: operand.playsBackwards, in: frame) }

            let source = operand.idFromParameter && operand.source == 0 ? Source.stackObject : Source(operand.source)
            guard let clip = try animation(id, from: source, in: frame) else { return .gotoTrue }
            switch operand.mode {
            case 0, 3:
                if operand.mode == 3 { sim.sim.carryAnimation = nil }
                return try playAndWait(clip, operand, sim, in: frame)
            case 2:
                sim.sim.carryAnimation = AnimationState(clip: clip)
                return .gotoTrue
            default:
                return .gotoTrue
            }
        }

        private static func playAndWait(_ clip: AnimationClip, _ operand: Operand, _ sim: Entity,
                                        in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            // Starting it, or progressing it?
            guard var current = sim.sim.animations.first, current.clip.key == clip.key else {
                sim.sim.animations = [AnimationState(clip: clip, playsBackwards: operand.playsBackwards)]
                sim.sim.leftHandPose = 0
                sim.sim.rightHandPose = 0
                return .continueNextTick
            }
            if current.endReached {
                while current.eventsRun < operand.expectedEventCount {
                    current.eventQueue.append(Int16(current.eventsRun))
                    current.eventsRun &+= 1
                }
            }
            // Events before the end: none may be missed.
            if !current.eventQueue.isEmpty {
                let event = current.eventQueue.removeFirst()
                sim.sim.animations[0] = current
                if operand.storesEventInLocal {
                    let index = Int(operand.localEventNumber)
                    guard index < frame.locals.count else { throw .indexOutOfRange("local \(index)") }
                    frame.locals[index] = event
                } else {
                    guard !frame.arguments.isEmpty else { throw .indexOutOfRange("parameter 0") }
                    frame.arguments[0] = event
                }
                return .gotoFalse
            }
            if current.endReached {
                sim.sim.animations = []
                return .gotoTrue
            }
            sim.sim.animations[0] = current
            return .continueNextTick
        }

        /// ID 0: everything stops, and the posture's walk animation plays, looping.
        private static func reset(_ sim: Entity, backwards: Bool, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            sim.sim.animations = []
            var posture = Int(sim.personData[PersonData.posture])
            if posture != 1 && posture != 2 { posture = 3 }
            guard let name = sim.sim.walkAnimations[posture], let walk = try frame.vm.animationClip(named: name) else {
                return .gotoTrue
            }
            sim.sim.animations = [AnimationState(clip: walk, playsBackwards: backwards, loops: true)]
            if sim.slot(0) != nil {
                if sim.sim.carryAnimation == nil, let carry = try frame.vm.animationClip(named: defaultCarry) {
                    sim.sim.carryAnimation = AnimationState(clip: carry)
                }
            } else {
                sim.sim.carryAnimation = nil
            }
            return .gotoTrue
        }

        /// Where an animation's name is looked up (`VMAnimationScope`).
        enum Source: Equatable {
            case object, global, personStock, misc, stackObject, unknown

            init(_ raw: UInt8) {
                self = switch raw {
                case 0: .object
                case 1: .global
                case 2: .personStock
                case 3: .misc
                default: .unknown
                }
            }
        }

        /// The animation an ID names in its source's table, or `nil` if there's no table, no name
        /// at that ID, or no animation by that name.
        static func animation(_ id: UInt16, from source: Source, in frame: StackFrame) throws(SimAnticsError) -> AnimationClip? {
            let table: STR?
            do {
                switch source {
                case .object:
                    table = try objectTable(of: frame.codeOwner)
                case .stackObject:
                    guard let stackObject = frame.stackObject else { return nil }
                    table = try objectTable(of: stackObject.object)
                case .global:
                    table = try frame.vm.global.chunk(STR.self, id: 128)
                case .personStock:
                    table = try frame.vm.global.chunk(STR.self, id: 130)
                case .misc:
                    table = try frame.vm.global.chunk(STR.self, id: 156)
                case .unknown:
                    table = nil
                }
            } catch {
                throw .simantics("an animation table doesn't parse: \(error)")
            }
            guard let name = table?.table.string(at: Int(id)) else { return nil }
            return try frame.vm.animationClip(named: name)
        }

        /// An object's animation table: the one its `OBJD` names, else `STR#` 129, in its own file
        /// only (FreeSO's `GameObjectResource.Get`).
        private static func objectTable(of object: GameObject) throws -> STR? {
            if let table = try object.resource.chunk(STR.self, id: object.definition.animationTableID) { return table }
            return try object.resource.chunk(STR.self, id: 129)
        }
    }
}
