import Testing
import CBOR

/// A type that encodes as a top-level *unkeyed* container, using the nesting
/// and `super` methods on it.
///
/// `ManualContainers` reaches the unkeyed container's per-primitive overloads,
/// but not these: `encodeNil()`, `nestedContainer(keyedBy:)`,
/// `nestedUnkeyedContainer()` and `superEncoder()` are only called by a
/// conformance that nests inside a list, which nothing else here does.
private struct NestedInList: Equatable {
    var flag: Bool
    var inner: Int32
    var deep: String
    var viaSuper: Int16
    var hadNil: Bool

    enum InnerKeys: String, CodingKey { case inner }
}

extension NestedInList: Codable {
    init(from decoder: any Decoder) throws {
        var list = try decoder.unkeyedContainer()
        flag = try list.decode(Bool.self)
        hadNil = try list.decodeNil()
        let nested = try list.nestedContainer(keyedBy: InnerKeys.self)
        inner = try nested.decode(Int32.self, forKey: .inner)
        var deeper = try list.nestedUnkeyedContainer()
        deep = try deeper.decode(String.self)
        viaSuper = try list.superDecoder().singleValueContainer().decode(Int16.self)
    }

    func encode(to encoder: any Encoder) throws {
        var list = encoder.unkeyedContainer()
        try list.encode(flag)
        try list.encodeNil()
        var nested = list.nestedContainer(keyedBy: InnerKeys.self)
        try nested.encode(inner, forKey: .inner)
        var deeper = list.nestedUnkeyedContainer()
        try deeper.encode(deep)
        do {
            var single = list.superEncoder().singleValueContainer()
            try single.encode(viaSuper)
        }
    }
}

/// Reads `userInfo`, which nothing else touches on either side.
private struct ReadsUserInfo: Codable, Equatable {
    var value: Int

    enum Keys: String, CodingKey { case value }

    init(value: Int) { self.value = value }

    init(from decoder: any Decoder) throws {
        _ = decoder.userInfo
        value = try decoder.container(keyedBy: Keys.self).decode(Int.self, forKey: .value)
    }

    func encode(to encoder: any Encoder) throws {
        _ = encoder.userInfo
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(value, forKey: .value)
    }
}

/// Asks for `superDecoder()` on a map that has no `"super"` key, which is the
/// only way to reach the `?? .null` fallback behind it.
private struct MissingSuper: Decodable {
    var recovered: Bool

    enum Keys: String, CodingKey { case other }

    init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        let sub = try keyed.superDecoder()
        recovered = try sub.singleValueContainer().decodeNil()
    }
}

@Suite("Coverage gaps")
struct CoverageGapTests {
    @Test("an unkeyed container's nesting and super methods round trip")
    func nestedInList() throws {
        let value = NestedInList(flag: true, inner: -70000, deep: "deep", viaSuper: -300, hadNil: true)
        let bytes = try CBOREncoder().encode(value)
        #expect(try CBORDecoder().decode(NestedInList.self, from: bytes) == value)
    }

    @Test("userInfo is readable from both sides")
    func userInfo() throws {
        let bytes = try CBOREncoder().encode(ReadsUserInfo(value: 42))
        #expect(try CBORDecoder().decode(ReadsUserInfo.self, from: bytes).value == 42)
    }

    @Test("superDecoder on a map without a super key yields null rather than throwing")
    func missingSuperKey() throws {
        // `{"other": 1}` — no "super" entry, so the fallback is what runs.
        let bytes = try CBOREncoder().encode(["other": 1])
        #expect(try CBORDecoder().decode(MissingSuper.self, from: bytes).recovered)
    }

    @Test("decode and decodeFirst accept an ArraySlice")
    func arraySliceOverloads() throws {
        let bytes = try CBOREncoder().encode(["a": 1, "b": 2])
        let padded: [UInt8] = [0xFF] + bytes + [0xFF]
        let slice = padded[1..<(padded.count - 1)]

        let whole = try CBOR.decode(slice)
        #expect(whole.mapValue?.count == 2)

        let (first, consumed) = try CBOR.decodeFirst(slice)
        #expect(first == whole)
        #expect(consumed == bytes.count)
    }

    @Test("arrayValue and mapValue return nil for the wrong shape")
    func shapeAccessors() throws {
        let array = try CBOR.decode(try CBOREncoder().encode([1, 2, 3]))
        #expect(array.arrayValue?.count == 3)
        #expect(array.mapValue == nil)

        let map = try CBOR.decode(try CBOREncoder().encode(["k": 1]))
        #expect(map.mapValue?.count == 1)
        #expect(map.arrayValue == nil)
    }

    @Test("CBORTag is constructible through RawRepresentable")
    func tagRawValue() {
        let tag = CBORTag(rawValue: 42)
        #expect(tag.rawValue == 42)
        #expect(tag == CBORTag(42))
        #expect(CBORTag.standardDateTimeString.rawValue == 0)
    }

    @Test("a float literal builds a CBOR value")
    func floatLiteral() {
        let value: CBOR = 1.5
        #expect(value.doubleValue == 1.5)
    }
}
