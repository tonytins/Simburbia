import Foundation
import Testing
import TSOFiles
@testable import TSOContent

/// The smallest `.anim`: version 2, a name, no tables, and no motions.
private func emptyAnimation(_ name: String) -> Data {
    var writer = ByteWriter(bigEndian: true)
    writer.uint32(2)
    writer.uint16(UInt16(name.utf8.count))
    writer.ascii(name)
    writer.uint32(0)                       // duration, a float, 0 in any byte order
    writer.uint32(0)                       // distance
    writer.uint8(0)                        // not moving
    writer.uint32(0)                       // translations
    writer.uint32(0)                       // rotations
    writer.uint32(0)                       // motions
    return writer.bytes
}

@Suite struct AnimationProviderTests {
    @Test func findsAnimationsByNameInAnyCaseTheLaterArchiveKeepingARepeatedOne() throws {
        let install = try FakeInstall()
        try install.write(makeFAR3([("A-Sit.anim", AssetID(fileID: 1, typeID: 7), emptyAnimation("first")),
                                    ("notes.txt", AssetID(fileID: 2, typeID: 1), Data("not an animation".utf8))]),
                          to: "avatardata/animations/animations.dat")
        try install.write(makeFAR3([("a-sit.anim", AssetID(fileID: 3, typeID: 7), emptyAnimation("second")),
                                    ("a-walk.anim", AssetID(fileID: 4, typeID: 7), emptyAnimation("walk"))]),
                          to: "avatardata/animations/more.DAT")
        try install.write(Data("not a FAR3".utf8), to: "avatardata/animations/broken.dat")
        try install.write(makeFAR3([("a-run.anim", AssetID(fileID: 5, typeID: 7), emptyAnimation("run"))]),
                          to: "avatardata/bodies/meshes/meshes.dat")
        let animations = AnimationProvider(files: try GameFileIndex(root: install.root))
        #expect(animations.names == ["a-sit.anim", "a-walk.anim"])
        #expect(try animations.animation(named: "A-SIT.anim")?.name == "second")
        #expect(animations.duplicates == ["a-sit.anim"])
        #expect(animations.failures.map(\.path) == ["avatardata/animations/broken.dat"])
        // Not under animations, and not there at all.
        #expect(try animations.animation(named: "a-run.anim") == nil)
        #expect(try animations.animation(named: "a-sit") == nil)
    }

    @Test func anAnimationThatDoesntDecodeThrows() throws {
        let install = try FakeInstall()
        try install.write(makeFAR3([("bad.anim", AssetID(fileID: 1, typeID: 7), Data([0, 0, 0, 2, 0]))]),
                          to: "avatardata/animations/animations.dat")
        let animations = AnimationProvider(files: try GameFileIndex(root: install.root))
        #expect(throws: ContentError.self) { try animations.animation(named: "bad.anim") }
    }

    /// MockInstall's six placeholder animations, made up by `generators/mock_avatar.py`, with
    /// their timed events; the dance is in the single-set layout, as TSO's stereo dances are, and
    /// the reach has the name Reach looks up for the floor.
    @Test func readsTheMockInstallsAnimations() throws {
        let animations = AnimationProvider(files: try GameFileIndex(root: mockInstall))
        #expect(animations.names == ["a2o-reach-floorht.anim", "mock-dance.anim", "mock-stand.anim", "mock-swim.anim", "mock-walk-fast.anim", "mock-walk.anim"])
        #expect(animations.failures.isEmpty && animations.duplicates.isEmpty)

        let walk = try #require(try animations.animation(named: "mock-walk.anim"))
        #expect(walk.isMoving && walk.frameCount == 30 && walk.duration == 1_000 && walk.motions.count == 4)
        #expect(walk.propertyLayout == .sets)
        #expect(walk.timedProperties.map(\.time) == [250, 750])
        #expect(walk.timedProperties.map { $0.properties["lefthand"] } == ["1", nil])

        let stand = try #require(try animations.animation(named: "mock-stand.anim"))
        #expect(stand.timedProperties.map(\.time) == [500, 800])
        #expect(stand.timedProperties[0].properties["xevt"] == "1" && stand.timedProperties[1].properties["sound"] == "mock_chime")

        let dance = try #require(try animations.animation(named: "mock-dance.anim"))
        #expect(dance.propertyLayout == .singleSet && dance.frameCount == 60)
        #expect(dance.timedProperties.map { $0.properties["xevt"] } == ["1", "2"])
        #expect(try animations.animation(named: "mock-swim.anim")?.timedProperties.isEmpty == true)
    }
}
