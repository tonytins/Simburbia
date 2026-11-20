import Foundation
import Testing
@testable import TSOFiles

/// Writes `.anim` files as TSO lays them out: big-endian, but with little-endian floats.
private struct AnimationWriter {
    var writer = ByteWriter(bigEndian: true)
    /// Writes property lists as one set with no set count, as `a2o-test-animation2` does.
    var singleSet = false

    mutating func float(_ value: Float) {
        let bits = value.bitPattern
        for shift in stride(from: 0, to: 32, by: 8) { writer.uint8(UInt8(truncatingIfNeeded: bits >> UInt32(shift))) }
    }

    mutating func pascal(_ text: String) {
        writer.uint8(UInt8(text.utf8.count))
        writer.ascii(text)
    }

    mutating func propertyList(_ items: [[(String, String)]]) {
        if !singleSet { writer.uint32(UInt32(items.count)) }
        for item in items {
            writer.uint32(UInt32(item.count))
            for (key, value) in item {
                pascal(key)
                pascal(value)
            }
        }
    }
}

/// A two-motion animation: a translated, rotated pelvis with an `xevt` at 500 ms and a sound at
/// 900 ms, and an arm with rotations only, a property list, and no timed properties.
private func sampleAnimation(singleSet: Bool = false) -> Data {
    var a = AnimationWriter(singleSet: singleSet)
    a.writer.uint32(2)
    a.writer.int16(5)
    a.writer.ascii("a-sit")
    a.float(1_000)
    a.float(1.5)
    a.writer.uint8(1)
    a.writer.uint32(2)
    for value: Float in [1, 2, 3, -4, 5.5, 6] { a.float(value) }
    a.writer.uint32(3)
    for value: Float in [0, 0, 0, 1, 0.5, 0.5, 0.5, 0.5, 0, 1, 0, 0] { a.float(value) }
    a.writer.uint32(2)

    a.writer.uint32(0)
    a.pascal("PELVIS")
    a.writer.uint32(30)
    a.float(1_000)
    a.writer.uint8(1)
    a.writer.uint8(1)
    a.writer.uint32(0)
    a.writer.uint32(1)
    a.writer.uint8(0)                     // no property lists
    a.writer.uint8(1)                     // timed properties
    a.writer.uint32(1)
    a.writer.uint32(2)
    a.writer.uint32(500)
    a.propertyList([[("xevt", "1")]])
    a.writer.uint32(900)
    a.propertyList([[("sound", "sit_down"), ("volume", "50")]])

    a.writer.uint32(0)
    a.pascal("R_ARM")
    a.writer.uint32(12)
    a.float(400)
    a.writer.uint8(0)
    a.writer.uint8(1)
    a.writer.uint32(0)
    a.writer.uint32(0)
    a.writer.uint8(1)                     // property lists
    a.writer.uint32(1)
    a.propertyList(singleSet ? [[("note", "b"), ("flag", "c")]] : [[("note", "a")], [("note", "b"), ("flag", "c")]])
    a.writer.uint8(0)                     // no timed properties
    return a.writer.bytes
}

@Suite struct AnimationTests {
    @Test func readsTheHeaderTablesAndMotions() throws {
        let animation = try Animation(bytes: sampleAnimation())
        #expect(animation.version == 2)
        #expect(animation.name == "a-sit")
        #expect(animation.duration == 1_000 && animation.distance == 1.5 && animation.isMoving)
        #expect(animation.translations == [SIMD3(1, 2, 3), SIMD3(-4, 5.5, 6)])
        #expect(animation.rotations == [SIMD4(0, 0, 0, 1), SIMD4(0.5, 0.5, 0.5, 0.5), SIMD4(0, 1, 0, 0)])
        #expect(animation.motions.map(\.boneName) == ["PELVIS", "R_ARM"])
        #expect(animation.frameCount == 30)

        let pelvis = animation.motions[0]
        #expect(pelvis.hasTranslation && pelvis.hasRotation && pelvis.firstRotationIndex == 1)
        #expect(pelvis.properties == nil)
        let arm = animation.motions[1]
        #expect(!arm.hasTranslation && arm.hasRotation && arm.duration == 400)
        #expect(arm.timedProperties == nil)
        #expect(arm.properties?.first?["flag"] == "c" && arm.properties?.first?["note"] == "a")
    }

    /// Floats are little-endian although the rest is big-endian, as FreeSO's `ReadFloat` reads them.
    @Test func readsFloatsLittleEndian() throws {
        var bytes = sampleAnimation()
        let durationOffset = 4 + 2 + 5
        #expect(Array(bytes[durationOffset..<durationOffset + 4]) == [0x00, 0x00, 0x7A, 0x44])  // 1000 as a little-endian float
        bytes[durationOffset + 3] = 0x45                                                        // 4000
        #expect(try Animation(bytes: bytes).duration == 4_000)
    }

    /// Times are signed: TSO's files hold negative ones, which FreeSO reads as unsigned.
    @Test func readsNegativeTimes() throws {
        var bytes = sampleAnimation()
        let first = try #require(bytes.firstRange(of: Data([0, 0, 0x01, 0xF4])))  // 500, the first event's time
        bytes.replaceSubrange(first, with: [0xFF, 0xFF, 0xDE, 0x04])              // -8700
        #expect(try Animation(bytes: bytes).timedProperties.map(\.time) == [-8_700, 900])
    }

    @Test func readsTimedPropertiesInFileOrder() throws {
        let events = try Animation(bytes: sampleAnimation()).timedProperties
        #expect(events.map(\.time) == [500, 900])
        #expect(events[0].properties["xevt"] == "1")
        #expect(events[1].properties["sound"] == "sit_down" && events[1].properties["volume"] == "50")
        #expect(events[1].properties["missing"] == nil)
    }

    @Test func anAnimationWithNoMotionsHasNoFrames() throws {
        var a = AnimationWriter()
        a.writer.uint32(2)
        a.writer.int16(0)
        a.float(0)
        a.float(0)
        a.writer.uint8(0)
        a.writer.uint32(0)
        a.writer.uint32(0)
        a.writer.uint32(0)
        let animation = try Animation(bytes: a.writer.bytes)
        #expect(animation.frameCount == 0 && animation.timedProperties.isEmpty && animation.name.isEmpty)
    }

    /// Cutting the file anywhere throws, never traps or returns part of an animation.
    @Test func everyTruncationThrows() {
        let bytes = sampleAnimation()
        for length in 0..<bytes.count {
            #expect(throws: AnimationError.self, "\(length) bytes") { try Animation(bytes: bytes.prefix(length)) }
        }
    }

    /// A count the bytes can't hold is refused before anything is allocated.
    @Test(arguments: [(offset: 4 + 2 + 5 + 9, what: "translations"),
                      (offset: 4 + 2 + 5 + 9 + 4 + 24, what: "rotations"),
                      (offset: 4 + 2 + 5 + 9 + 4 + 24 + 4 + 48, what: "motions")])
    func refusesACountTooLargeForTheData(offset: Int, what: String) {
        var bytes = sampleAnimation()
        for i in 0..<4 { bytes[offset + i] = 0xFF }
        #expect {
            try Animation(bytes: bytes)
        } throws: { error in
            guard case .countTooLarge(let name, let count, _) = error as? AnimationError else { return false }
            return name == what && count == 0xFFFF_FFFF
        }
    }

    @Test func refusesANegativeNameLength() {
        var bytes = sampleAnimation()
        bytes[4] = 0xFF
        bytes[5] = 0xFE
        #expect(throws: AnimationError.negativeLength("name")) { try Animation(bytes: bytes) }
    }

    /// A file written with single-set property lists, as the stereos' dance animations are, reads
    /// in that layout, where FreeSO fails (DIFF-35).
    @Test func readsTheSingleSetLayout() throws {
        let animation = try Animation(bytes: sampleAnimation(singleSet: true))
        #expect(animation.propertyLayout == .singleSet)
        #expect(animation.timedProperties.map(\.time) == [500, 900])
        #expect(animation.timedProperties[1].properties["volume"] == "50")
        #expect(animation.motions[1].properties?.first?["flag"] == "c")
        #expect(try Animation(bytes: sampleAnimation()).propertyLayout == .sets)
    }

    /// The single-set layout is a second reading, so it has to account for every byte; the
    /// usual layout's error is the one reported.
    @Test func theSingleSetLayoutMustEndWithTheFile() {
        #expect(throws: AnimationError.self) { try Animation(bytes: sampleAnimation(singleSet: true) + Data([0])) }
        for length in 0..<sampleAnimation(singleSet: true).count {
            #expect(throws: AnimationError.self, "\(length) bytes") { try Animation(bytes: sampleAnimation(singleSet: true).prefix(length)) }
        }
    }

    /// Bytes past the last motion are ignored, as in FreeSO.
    @Test func ignoresTrailingBytes() throws {
        #expect(try Animation(bytes: sampleAnimation() + Data([1, 2, 3])) == Animation(bytes: sampleAnimation()))
    }
}
