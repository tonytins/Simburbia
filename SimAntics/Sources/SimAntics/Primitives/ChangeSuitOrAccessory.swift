import TSOContent
import TSOFiles

extension Primitives {
    /// Changes the calling Sim's outfit, or binds or unbinds an accessory (opcode 6).
    ///
    /// As state: what a client draws is its own concern. Of 1.1097.1.0's 3,001 instructions, 2,894
    /// use the object's suits:
    ///
    /// - **Object** (scope 2) and **global** (0) suits are appearance files named in `STR#` 304 of
    ///   the code owner or the global: each binds that `.apr` over the body
    ///   (``SimState/boundAppearances``), or with flag 1 unbinds it.
    /// - **Person** suits (scope 1) are the Sim's own: the default daywear, swimwear, and
    ///   sleepwear, naked, the online job's uniform, the skeletons, the teleporter mishap, and the
    ///   dynamic suits change the body outfit and set `CurrentOutfit` to the suit's index. The rest,
    ///   the decorations (8 to 11) among them, are accessories only drawing shows, and change
    ///   nothing here.
    /// - With flag 4 and the object scope, the default daywear becomes the outfit `STR#` 304 of the
    ///   callee's object names at the index in temp 0, and the Sim wears it.
    ///
    /// It goes true. A missing name skips the change; a missing table, or an outfit name that
    /// isn't a hexadecimal ID, is an error for the routine; so is a job uniform's grade past 12,
    /// since the uniforms come in three levels.
    public enum ChangeSuitOrAccessory: Primitive {
        public static let name = "change_suit_or_accessory"
        public static let opcode: UInt8 = 6

        /// The operand.
        public struct Operand: PrimitiveOperand, Equatable {
            public var suitData: UInt8
            /// Where the suit comes from: 0 global, 1 person, 2 object.
            public var suitScope: UInt8
            /// 1 removes an accessory; 4 updates the default daywear.
            public var flags: UInt16

            public init(suitData: UInt8, suitScope: UInt8, flags: UInt16 = 0) {
                self.suitData = suitData
                self.suitScope = suitScope
                self.flags = flags
            }

            public init(bytes: [UInt8]) {
                var reader = OperandReader(bytes)
                suitData = reader.uint8()
                suitScope = reader.uint8()
                flags = reader.uint16()
            }

            public func encoded() -> [UInt8] {
                OperandWriter.bytes { writer in
                    writer.uint8(suitData)
                    writer.uint8(suitScope)
                    writer.uint16(flags)
                }
            }

            public var removes: Bool { flags & 1 != 0 }
            public var updatesDaywear: Bool { flags & 4 != 0 }
        }

        /// The online jobs' uniforms (robot, waiter, cook, DJ, dancer), three levels each, male
        /// then female.
        static let jobOutfits: [[[UInt64]]] = [
            [[0x587_0000_000D, 0x588_0000_000D, 0x589_0000_000D], [0x58B_0000_000D, 0x58D_0000_000D, 0x58E_0000_000D],
             [0x58A_0000_000D, 0x58C_0000_000D, 0x58F_0000_000D], [0x590_0000_000D, 0x592_0000_000D, 0x594_0000_000D],
             [0x591_0000_000D, 0x593_0000_000D, 0x595_0000_000D]],
            [[0x578_0000_000D, 0x579_0000_000D, 0x57A_0000_000D], [0x57C_0000_000D, 0x57E_0000_000D, 0x57F_0000_000D],
             [0x57B_0000_000D, 0x57D_0000_000D, 0x580_0000_000D], [0x581_0000_000D, 0x583_0000_000D, 0x585_0000_000D],
             [0x582_0000_000D, 0x584_0000_000D, 0x586_0000_000D]],
        ]

        public static func execute(_ operand: Operand, in frame: StackFrame) throws(SimAnticsError) -> ExitCode {
            guard let sim = frame.caller, sim.isAvatar else { throw .invalidCast("Change Suit's caller isn't a Sim") }
            switch operand.suitScope {
            case 2 where operand.updatesDaywear:
                guard let callee = frame.callee else { throw .nullReference("Change Suit has no callee") }
                let name = try table(304, in: callee.object.resource)?.string(at: Int(frame.thread.tempRegisters[0]))
                guard let name, let outfit = Entity.outfitID(name) else {
                    throw .simantics("no daywear outfit at \(frame.thread.tempRegisters[0]) in STR# 304")
                }
                sim.sim.daywear = outfit
                sim.sim.bodyOutfit = outfit
            case 0, 2:
                let resource: any IFFResource = operand.suitScope == 0 ? frame.vm.global : frame.codeOwner.resource
                guard let name = try table(304, in: resource)?.string(at: Int(operand.suitData)) else { return .gotoTrue }
                let file = name + ".apr"
                if operand.removes {
                    if let index = sim.sim.boundAppearances.firstIndex(of: file) { sim.sim.boundAppearances.remove(at: index) }
                } else {
                    sim.sim.boundAppearances.append(file)
                }
            case 1:
                guard let outfit = try bodyOutfit(Int(operand.suitData), of: sim) else { return .gotoTrue }
                sim.personData[PersonData.currentOutfit] = Int16(operand.suitData)
                sim.sim.bodyOutfit = outfit
            default:
                break
            }
            return .gotoTrue
        }

        /// A person suit that changes the body, or `nil` for one that's an accessory or unknown.
        static func bodyOutfit(_ suit: Int, of sim: Entity) throws(SimAnticsError) -> UInt64? {
            let male = sim.personData[PersonData.gender] == 0
            switch suit {
            case 0: return sim.sim.daywear
            case 1: return male ? 0x24E_0000_000D : 0x1_0000_000D
            case 2: return sim.sim.swimwear
            case 3:
                let job = Int(sim.personData[PersonData.onlineJobID])
                guard (1...5).contains(job) else { return nil }
                let level = max(0, min(3, (Int(sim.personData[PersonData.onlineJobGrade]) - 1) / 4))
                let levels = jobOutfits[male ? 0 : 1][job - 1]
                guard levels.indices.contains(level) else { throw .indexOutOfRange("job outfit level \(level)") }
                return levels[level]
            case 5: return sim.sim.sleepwear
            case 6: return 0x575_0000_000D
            case 7: return 0x574_0000_000D
            case 20: return male ? 0x290_0000_000D : 0x4A_0000_000D
            case 22: return sim.sim.dynamicDaywear
            case 23: return sim.sim.dynamicSwimwear
            case 24: return sim.sim.dynamicSleepwear
            case 25: return sim.sim.dynamicCostume
            default: return nil
            }
        }

        private static func table(_ id: UInt16, in resource: any IFFResource) throws(SimAnticsError) -> StringTable? {
            do {
                return try resource.chunk(STR.self, id: id)?.table
            } catch {
                throw .simantics("STR# \(id) doesn't parse: \(error)")
            }
        }
    }
}
