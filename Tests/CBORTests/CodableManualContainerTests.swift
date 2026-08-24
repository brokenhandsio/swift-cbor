import Testing
import CBOR

/// Reaches the container methods a *synthesized* `Codable` conformance never
/// calls.
///
/// This is not a stylistic preference — it is the only way to reach the code.
/// `Array`'s own conformance decodes its elements through the generic
/// `decode<T: Decodable>`, so a property of type `[Int32]` never touches
/// `UnkeyedContainer.decode(Int32.self)`. The same is true of every concrete
/// overload in every container: they exist for hand-written conformances, and
/// only a hand-written conformance executes them.
///
/// Each line below is aimed at a specific method the coverage report listed as
/// unexecuted.
private struct ManualContainers: Equatable {
    // Reached through `superEncoder(forKey:)` / `superDecoder(forKey:)`, then a
    // single-value container each — which covers two uncovered groups at once.
    var bool: Bool
    var string: String
    var double: Double
    var float: Float
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

    // Written into one unkeyed container, in this order, one primitive each.
    var listBool: Bool
    var listString: String
    var listDouble: Double
    var listFloat: Float
    var listInt: Int
    var listInt8: Int8
    var listInt16: Int16
    var listInt32: Int32
    var listInt64: Int64
    var listUInt: UInt
    var listUInt8: UInt8
    var listUInt16: UInt16
    var listUInt32: UInt32
    var listUInt64: UInt64

    // A nested keyed container, and an explicit nil.
    var nestedValue: Int16
    var nilPresent: Bool

    enum Keys: String, CodingKey {
        case bool, string, double, float
        case int, int8, int16, int32, int64
        case uint, uint8, uint16, uint32, uint64
        case list, nested, nothing
    }

    enum NestedKeys: String, CodingKey { case value }

}

// In an extension so the memberwise initialiser is still synthesized: writing
// `init(from:)` in the body would suppress it.
extension ManualContainers: Codable {
    init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)

        // `superDecoder(forKey:)` hands back a decoder for that key; asking it
        // for a single-value container is what reaches the concrete
        // `SingleValueContainer.decode` overloads.
        bool = try keyed.superDecoder(forKey: .bool).singleValueContainer().decode(Bool.self)
        string = try keyed.superDecoder(forKey: .string).singleValueContainer().decode(String.self)
        double = try keyed.superDecoder(forKey: .double).singleValueContainer().decode(Double.self)
        float = try keyed.superDecoder(forKey: .float).singleValueContainer().decode(Float.self)
        int = try keyed.superDecoder(forKey: .int).singleValueContainer().decode(Int.self)
        int8 = try keyed.superDecoder(forKey: .int8).singleValueContainer().decode(Int8.self)
        int16 = try keyed.superDecoder(forKey: .int16).singleValueContainer().decode(Int16.self)
        int32 = try keyed.superDecoder(forKey: .int32).singleValueContainer().decode(Int32.self)
        int64 = try keyed.superDecoder(forKey: .int64).singleValueContainer().decode(Int64.self)
        uint = try keyed.superDecoder(forKey: .uint).singleValueContainer().decode(UInt.self)
        uint8 = try keyed.superDecoder(forKey: .uint8).singleValueContainer().decode(UInt8.self)
        uint16 = try keyed.superDecoder(forKey: .uint16).singleValueContainer().decode(UInt16.self)
        uint32 = try keyed.superDecoder(forKey: .uint32).singleValueContainer().decode(UInt32.self)
        uint64 = try keyed.superDecoder(forKey: .uint64).singleValueContainer().decode(UInt64.self)

        var list = try keyed.nestedUnkeyedContainer(forKey: .list)
        // Touched so the getter runs; asserted in the tests.
        _ = list.count
        listBool = try list.decode(Bool.self)
        listString = try list.decode(String.self)
        listDouble = try list.decode(Double.self)
        listFloat = try list.decode(Float.self)
        listInt = try list.decode(Int.self)
        listInt8 = try list.decode(Int8.self)
        listInt16 = try list.decode(Int16.self)
        listInt32 = try list.decode(Int32.self)
        listInt64 = try list.decode(Int64.self)
        listUInt = try list.decode(UInt.self)
        listUInt8 = try list.decode(UInt8.self)
        listUInt16 = try list.decode(UInt16.self)
        listUInt32 = try list.decode(UInt32.self)
        listUInt64 = try list.decode(UInt64.self)
        _ = list.isAtEnd

        let nested = try keyed.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
        nestedValue = try nested.decode(Int16.self, forKey: .value)

        nilPresent = try keyed.decodeNil(forKey: .nothing)
    }

    func encode(to encoder: any Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)

        do { var c = keyed.superEncoder(forKey: .bool).singleValueContainer()
             try c.encode(bool) }
        do { var c = keyed.superEncoder(forKey: .string).singleValueContainer()
             try c.encode(string) }
        do { var c = keyed.superEncoder(forKey: .double).singleValueContainer()
             try c.encode(double) }
        do { var c = keyed.superEncoder(forKey: .float).singleValueContainer()
             try c.encode(float) }
        do { var c = keyed.superEncoder(forKey: .int).singleValueContainer()
             try c.encode(int) }
        do { var c = keyed.superEncoder(forKey: .int8).singleValueContainer()
             try c.encode(int8) }
        do { var c = keyed.superEncoder(forKey: .int16).singleValueContainer()
             try c.encode(int16) }
        do { var c = keyed.superEncoder(forKey: .int32).singleValueContainer()
             try c.encode(int32) }
        do { var c = keyed.superEncoder(forKey: .int64).singleValueContainer()
             try c.encode(int64) }
        do { var c = keyed.superEncoder(forKey: .uint).singleValueContainer()
             try c.encode(uint) }
        do { var c = keyed.superEncoder(forKey: .uint8).singleValueContainer()
             try c.encode(uint8) }
        do { var c = keyed.superEncoder(forKey: .uint16).singleValueContainer()
             try c.encode(uint16) }
        do { var c = keyed.superEncoder(forKey: .uint32).singleValueContainer()
             try c.encode(uint32) }
        do { var c = keyed.superEncoder(forKey: .uint64).singleValueContainer()
             try c.encode(uint64) }

        var list = keyed.nestedUnkeyedContainer(forKey: .list)
        try list.encode(listBool)
        try list.encode(listString)
        try list.encode(listDouble)
        try list.encode(listFloat)
        try list.encode(listInt)
        try list.encode(listInt8)
        try list.encode(listInt16)
        try list.encode(listInt32)
        try list.encode(listInt64)
        try list.encode(listUInt)
        try list.encode(listUInt8)
        try list.encode(listUInt16)
        try list.encode(listUInt32)
        try list.encode(listUInt64)
        _ = list.count

        var nested = keyed.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
        try nested.encode(nestedValue, forKey: .value)

        try keyed.encodeNil(forKey: .nothing)
    }

}

extension ManualContainers {
    static let sample = ManualContainers(
        bool: true, string: "s", double: -2.5, float: 0.25,
        int: -1, int8: -8, int16: -16, int32: -32, int64: .min,
        uint: 1, uint8: .max, uint16: .max, uint32: .max, uint64: .max,
        listBool: false, listString: "t", listDouble: 1e300, listFloat: -0.5,
        listInt: .max, listInt8: .min, listInt16: .min, listInt32: .min, listInt64: -64,
        listUInt: 7, listUInt8: 8, listUInt16: 16, listUInt32: 32, listUInt64: 64,
        nestedValue: -300, nilPresent: true
    )
}

@Suite("Codable manual containers")
struct CodableManualContainerTests {
    @Test("every concrete container overload round trips")
    func manualContainersRoundTrip() throws {
        let bytes = try CBOREncoder().encode(ManualContainers.sample)
        #expect(try CBORDecoder().decode(ManualContainers.self, from: bytes) == ManualContainers.sample)
    }

    @Test("hand-written containers are a fixed point under deterministic encoding")
    func manualContainersFixedPoint() throws {
        let options = CBOROptions(deterministic: true)
        let encoder = CBOREncoder(options: options)
        let once = try encoder.encode(ManualContainers.sample)
        let decoded = try CBORDecoder(options: options).decode(ManualContainers.self, from: once)
        #expect(try encoder.encode(decoded) == once)
    }
}
