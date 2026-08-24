import Testing
import CBOR

/// A type shaped to reach as much of the `Codable` bridge as one type can.
///
/// The bridge's containers implement `decode`/`encode` once per concrete type —
/// `Int8`, `Int16`, `UInt32`, `Float` and the rest each get their own method,
/// in both the keyed and the unkeyed container. A test using only `Int` and
/// `String` therefore leaves most of them unexecuted, which is what the
/// coverage report showed: 38% of the decoder's functions and 39% of the
/// encoder's, against 99% for the parser the fuzzers hammer.
///
/// Every stored property here exists to reach a specific one of those methods.
struct Everything: Codable, Equatable {
    struct Nested: Codable, Equatable {
        var small: Int8
        var wide: Double
    }

    var flag: Bool
    var text: String

    // One property per integer width, keyed. Each reaches a different
    // `KeyedContainer.decode(_:forKey:)` overload and a different `unboxSigned`
    // or `unboxUnsigned` specialisation.
    var int: Int
    var int8: Int8
    var int16: Int16
    var int32: Int32
    var int64: Int64
    var uint: UInt
    var uint8: UInt8
    var uint16: UInt16
    var uint32: UInt32
    var uint64: UInt64

    var float: Float
    var double: Double

    // Present and absent, so `decodeNil` is reached both ways.
    var presentOptional: String?
    var absentOptional: String?

    // A nested keyed container.
    var nested: Nested

    // Unkeyed containers: of a sized integer, of a nested type, and nested
    // inside one another.
    var numbers: [Int32]
    var nestedArrays: [[UInt8]]
    var records: [Nested]
    var optionals: [String?]

    // A map with non-trivial keys.
    var lookup: [String: Int16]

    static let sample = Everything(
        flag: true,
        text: "hello",
        int: -1, int8: -8, int16: -16, int32: -32, int64: -64,
        uint: 1, uint8: 8, uint16: 16, uint32: 32, uint64: 64,
        float: 0.5,
        double: -2.25,
        presentOptional: "here",
        absentOptional: nil,
        nested: Nested(small: 7, wide: 1e100),
        numbers: [1, -2, 3],
        nestedArrays: [[1, 2], [], [255]],
        records: [Nested(small: -1, wide: 0), Nested(small: 127, wide: -0.0)],
        optionals: ["a", nil, "c"],
        lookup: ["one": 1, "two": 2]
    )
}

/// Exercises `superEncoder`/`superDecoder`, which nothing else reaches.
///
/// They exist for class hierarchies, where a subclass hands the superclass its
/// own nested container to decode from.
private class Base: Codable, Equatable {
    var base: Int32
    init(base: Int32) { self.base = base }

    static func == (lhs: Base, rhs: Base) -> Bool { lhs.base == rhs.base }
}

private final class Derived: Base {
    var derived: String

    private enum CodingKeys: String, CodingKey { case derived }

    init(base: Int32, derived: String) {
        self.derived = derived
        super.init(base: base)
    }

    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        derived = try container.decode(String.self, forKey: .derived)
        try super.init(from: container.superDecoder())
    }

    override func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(derived, forKey: .derived)
        try super.encode(to: container.superEncoder())
    }
}

@Suite("Codable containers")
struct CodableContainerTests {
    @Test("every integer width, float and container shape survives a round trip")
    func everythingRoundTrips() throws {
        let bytes = try CBOREncoder().encode(Everything.sample)
        let decoded = try CBORDecoder().decode(Everything.self, from: bytes)
        #expect(decoded == Everything.sample)
    }

    @Test("round trip is a fixed point under deterministic encoding")
    func deterministicFixedPoint() throws {
        // Only under `deterministic`: with it off, map keys are emitted in
        // `Dictionary` order, which differs between two separately decoded
        // values, so a map with more than one entry can legitimately encode two
        // ways. `lookup` has two.
        let options = CBOROptions(deterministic: true)
        let encoder = CBOREncoder(options: options)
        let once = try encoder.encode(Everything.sample)
        let decoded = try CBORDecoder(options: options).decode(Everything.self, from: once)
        #expect(try encoder.encode(decoded) == once)
    }

    @Test("decoding accepts an ArraySlice as well as an Array")
    func decodeFromSlice() throws {
        let bytes = try CBOREncoder().encode(Everything.sample)
        // Padded on both sides, so the slice genuinely does not start at zero.
        let padded = [0xFF] + bytes + [0xFF]
        let slice = padded[1..<(padded.count - 1)]
        #expect(try CBORDecoder().decode(Everything.self, from: slice) == Everything.sample)
    }

    @Test("an absent optional decodes as nil rather than failing")
    func absentOptional() throws {
        let bytes = try CBOREncoder().encode(Everything.sample)
        let decoded = try CBORDecoder().decode(Everything.self, from: bytes)
        #expect(decoded.absentOptional == nil)
        #expect(decoded.presentOptional == "here")
        // Inside an unkeyed container too, which is a different `decodeNil`.
        #expect(decoded.optionals == ["a", nil, "c"])
    }

    @Test("an empty unkeyed container round trips")
    func emptyContainers() throws {
        var value = Everything.sample
        value.numbers = []
        value.records = []
        value.nestedArrays = []
        value.lookup = [:]
        let bytes = try CBOREncoder().encode(value)
        #expect(try CBORDecoder().decode(Everything.self, from: bytes) == value)
    }

    @Test("superEncoder and superDecoder carry a superclass's storage")
    func classInheritance() throws {
        let original = Derived(base: -12345, derived: "sub")
        let bytes = try CBOREncoder().encode(original)
        let decoded = try CBORDecoder().decode(Derived.self, from: bytes)
        #expect(decoded.base == original.base)
        #expect(decoded.derived == original.derived)
    }

    @Test("integer widths keep their exact values at the extremes", arguments: [
        (Int8.min, Int8.max), (-1, 1),
    ] as [(Int8, Int8)])
    func integerExtremes(low: Int8, high: Int8) throws {
        var value = Everything.sample
        value.int8 = low
        value.nested.small = high
        value.int64 = .min
        value.uint64 = .max
        value.int32 = .min
        value.uint32 = .max
        let bytes = try CBOREncoder().encode(value)
        #expect(try CBORDecoder().decode(Everything.self, from: bytes) == value)
    }

    @Test("a decode of the wrong type throws rather than trapping")
    func typeMismatchThrows() throws {
        let bytes = try CBOREncoder().encode(Everything.sample)
        #expect(throws: (any Error).self) {
            _ = try CBORDecoder().decode(Everything.Nested.self, from: bytes)
        }
    }
}
