import Foundation

/// A Sim's animation: a `.anim` file from the FAR3 archives under `avatardata/animations`.
///
/// The Sims 1's BCF animations aren't read here. An animation is a set of motions, one per
/// bone it moves, each a run of frames at 30 a second that index into shared tables of
/// translations and rotations. A motion can carry timed properties: events, such as a sound or
/// `xevt`, that fire when playback passes their time.
///
/// The file is big-endian, except that every float is little-endian whatever the stream's byte
/// order. Translations and rotations are kept as the file stores them; turning them into a
/// renderer's coordinates is up to whatever draws them. Bytes after the last motion are
/// ignored.
///
/// A few of TSO's animations (`a2o-test-animation2` to `6`, which the DJ booth, jukebox, and
/// stereos name) write each property list as a single set with no set count, the layout of The
/// Sims 1's BCF files. A file that doesn't read in the usual layout is read again in that one,
/// and kept only if it then ends exactly at the end of the data; ``propertyLayout`` says which
/// it took (DIFF-35 in the scorecard).
public struct Animation: Sendable, Equatable {
    /// How the file lays out its property lists.
    public enum PropertyLayout: Sendable, Equatable {
        /// A count of sets, each a count of pairs: TSO's usual layout.
        case sets
        /// One set of pairs, with no count of sets.
        case singleSet
    }

    /// A key and value from a property list, such as `xevt` and `1`.
    public struct Property: Sendable, Equatable {
        public var key: String
        public var value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    /// A list of property sets.
    public struct PropertyList: Sendable, Equatable {
        public var items: [[Property]]

        public init(items: [[Property]]) {
            self.items = items
        }

        /// The first value for `key`, searching each set in order.
        public subscript(key: String) -> String? {
            for item in items {
                if let property = item.first(where: { $0.key == key }) { return property.value }
            }
            return nil
        }
    }

    /// Properties that take effect at a time in the animation.
    public struct TimedProperties: Sendable, Equatable {
        /// When they take effect, in milliseconds from the start. Signed: 363 of 1.1097.1.0's
        /// animations hold negative times.
        public var time: Int32
        public var properties: PropertyList

        public init(time: Int32, properties: PropertyList) {
            self.time = time
            self.properties = properties
        }
    }

    /// One bone's part of the animation.
    public struct Motion: Sendable, Equatable {
        public var boneName: String
        public var frameCount: UInt32
        /// In milliseconds.
        public var duration: Float
        public var hasTranslation: Bool
        public var hasRotation: Bool
        /// The motion's first frame in ``Animation/translations``, if it has translations.
        public var firstTranslationIndex: UInt32
        /// The motion's first frame in ``Animation/rotations``, if it has rotations.
        public var firstRotationIndex: UInt32
        /// `nil` when the file says the motion has none.
        public var properties: [PropertyList]?
        /// Lists of timed properties, each in file order; `nil` when the file says it has none.
        public var timedProperties: [[TimedProperties]]?

        public init(boneName: String, frameCount: UInt32, duration: Float, hasTranslation: Bool = false,
                    hasRotation: Bool = false, firstTranslationIndex: UInt32 = 0, firstRotationIndex: UInt32 = 0,
                    properties: [PropertyList]? = nil, timedProperties: [[TimedProperties]]? = nil) {
            self.boneName = boneName
            self.frameCount = frameCount
            self.duration = duration
            self.hasTranslation = hasTranslation
            self.hasRotation = hasRotation
            self.firstTranslationIndex = firstTranslationIndex
            self.firstRotationIndex = firstRotationIndex
            self.properties = properties
            self.timedProperties = timedProperties
        }
    }

    /// The file's version, read and ignored; TSO's files hold 2.
    public var version: UInt32
    public var name: String
    /// In milliseconds.
    public var duration: Float
    public var distance: Float
    /// Whether the animation moves the Sim along (a walk), not only in place.
    public var isMoving: Bool
    /// Each a vector of x, y, and z.
    public var translations: [SIMD3<Float>]
    /// Each a quaternion of x, y, z, and w.
    public var rotations: [SIMD4<Float>]
    public var motions: [Motion]
    public var propertyLayout: PropertyLayout

    /// The animation's length in frames: its longest motion's.
    public var frameCount: UInt32 {
        motions.map(\.frameCount).max() ?? 0
    }

    /// Every motion's timed properties, in motion and then file order.
    public var timedProperties: [TimedProperties] {
        motions.flatMap { $0.timedProperties?.flatMap { $0 } ?? [] }
    }

    /// Reads a `.anim` file.
    ///
    /// - Throws: ``AnimationError`` if the data ends early or holds a count or length it can't,
    ///   in both layouts; the error is the usual layout's. Every count is checked against the
    ///   bytes left before anything is allocated.
    public init(bytes: Data) throws(AnimationError) {
        do {
            self = try Self.read(bytes, layout: .sets)
        } catch {
            guard let reread = try? Self.read(bytes, layout: .singleSet, toTheEnd: true) else { throw error }
            self = reread
        }
    }

    public init(version: UInt32 = 2, name: String, duration: Float, distance: Float = 0, isMoving: Bool = false,
                translations: [SIMD3<Float>] = [], rotations: [SIMD4<Float>] = [], motions: [Motion],
                propertyLayout: PropertyLayout = .sets) {
        self.version = version
        self.name = name
        self.duration = duration
        self.distance = distance
        self.isMoving = isMoving
        self.translations = translations
        self.rotations = rotations
        self.motions = motions
        self.propertyLayout = propertyLayout
    }

    private static func read(_ bytes: Data, layout: PropertyLayout, toTheEnd: Bool = false) throws(AnimationError) -> Animation {
        var reader = ByteReader(bytes, byteOrder: .bigEndian)
        do {
            let version = try reader.readUInt32()
            guard let name = try reader.readLongPascalString() else { throw AnimationError.negativeLength("name") }
            let duration = try readFloat(&reader)
            let distance = try readFloat(&reader)
            let isMoving = try reader.readUInt8() != 0

            let translationCount = try count(&reader, "translations", eachAtLeast: 12)
            var translations: [SIMD3<Float>] = []
            translations.reserveCapacity(translationCount)
            for _ in 0..<translationCount {
                translations.append(SIMD3(try readFloat(&reader), try readFloat(&reader), try readFloat(&reader)))
            }

            let rotationCount = try count(&reader, "rotations", eachAtLeast: 16)
            var rotations: [SIMD4<Float>] = []
            rotations.reserveCapacity(rotationCount)
            for _ in 0..<rotationCount {
                rotations.append(SIMD4(try readFloat(&reader), try readFloat(&reader), try readFloat(&reader), try readFloat(&reader)))
            }

            // A motion is at least 26 bytes: an unknown word, an empty bone name, the frame
            // count, the duration, two flags, two indexes, and two "has a list" flags.
            let motionCount = try count(&reader, "motions", eachAtLeast: 26)
            var motions: [Motion] = []
            motions.reserveCapacity(motionCount)
            for _ in 0..<motionCount {
                motions.append(try readMotion(&reader, layout: layout))
            }
            if toTheEnd, reader.remaining != 0 {
                throw AnimationError.trailingBytes(reader.remaining)
            }
            return Animation(version: version, name: name, duration: duration, distance: distance, isMoving: isMoving,
                             translations: translations, rotations: rotations, motions: motions, propertyLayout: layout)
        } catch let error as EndOfDataError {
            throw .truncated(error)
        } catch let error as AnimationError {
            throw error
        } catch {
            // Not reached: the reads throw only the two errors above.
            throw .truncated(EndOfDataError(offset: reader.offset, needed: 0, available: reader.remaining))
        }
    }

    private static func readMotion(_ reader: inout ByteReader, layout: PropertyLayout) throws -> Motion {
        _ = try reader.readUInt32()  // unknown, read and ignored as in FreeSO
        let boneName = try reader.readPascalString()
        let frameCount = try reader.readUInt32()
        let duration = try readFloat(&reader)
        let hasTranslation = try reader.readUInt8() == 1
        let hasRotation = try reader.readUInt8() == 1
        let firstTranslationIndex = try reader.readUInt32()
        let firstRotationIndex = try reader.readUInt32()

        var properties: [PropertyList]?
        if try reader.readUInt8() == 1 {
            let listCount = try count(&reader, "property lists", eachAtLeast: 4)
            var lists: [PropertyList] = []
            lists.reserveCapacity(listCount)
            for _ in 0..<listCount { lists.append(try readPropertyList(&reader, layout: layout)) }
            properties = lists
        }

        var timedProperties: [[TimedProperties]]?
        if try reader.readUInt8() == 1 {
            let listCount = try count(&reader, "timed property lists", eachAtLeast: 4)
            var lists: [[TimedProperties]] = []
            lists.reserveCapacity(listCount)
            for _ in 0..<listCount {
                let itemCount = try count(&reader, "timed properties", eachAtLeast: 8)
                var items: [TimedProperties] = []
                items.reserveCapacity(itemCount)
                for _ in 0..<itemCount {
                    let time = try reader.readInt32()
                    items.append(TimedProperties(time: time, properties: try readPropertyList(&reader, layout: layout)))
                }
                lists.append(items)
            }
            timedProperties = lists
        }

        return Motion(boneName: boneName, frameCount: frameCount, duration: duration, hasTranslation: hasTranslation,
                      hasRotation: hasRotation, firstTranslationIndex: firstTranslationIndex,
                      firstRotationIndex: firstRotationIndex, properties: properties, timedProperties: timedProperties)
    }

    private static func readPropertyList(_ reader: inout ByteReader, layout: PropertyLayout) throws -> PropertyList {
        let itemCount = layout == .sets ? try count(&reader, "property sets", eachAtLeast: 4) : 1
        var items: [[Property]] = []
        items.reserveCapacity(itemCount)
        for _ in 0..<itemCount {
            let pairCount = try count(&reader, "properties", eachAtLeast: 2)
            var pairs: [Property] = []
            pairs.reserveCapacity(pairCount)
            for _ in 0..<pairCount {
                pairs.append(Property(key: try reader.readPascalString(), value: try reader.readPascalString()))
            }
            items.append(pairs)
        }
        return PropertyList(items: items)
    }

    /// A 32-bit count, refused if that many entries of at least `size` bytes can't fit in what's left.
    private static func count(_ reader: inout ByteReader, _ what: String, eachAtLeast size: Int) throws -> Int {
        let count = Int(try reader.readUInt32())
        let (needed, overflow) = count.multipliedReportingOverflow(by: size)
        guard !overflow, needed <= reader.remaining else {
            throw AnimationError.countTooLarge(what, count: count, remaining: reader.remaining)
        }
        return count
    }

    /// A little-endian float from the big-endian reader: its word read big-endian, then swapped.
    private static func readFloat(_ reader: inout ByteReader) throws(EndOfDataError) -> Float {
        Float(bitPattern: try reader.readUInt32().byteSwapped)
    }
}

/// An error reading a `.anim` file.
public enum AnimationError: Error, Equatable, Sendable {
    case truncated(EndOfDataError)
    /// A string's length is negative.
    case negativeLength(String)
    /// A count of something can't fit in the bytes that remain.
    case countTooLarge(String, count: Int, remaining: Int)
    /// Read in the single-set layout, the file didn't end where the animation did.
    case trailingBytes(Int)
}
