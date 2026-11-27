import Testing
import CBOR

// MARK: - Fixtures

/// Writes the same key twice, the second time with a different value.
private struct RepeatedKey: Encodable {
    enum CodingKeys: String, CodingKey { case a, b }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .b)
        try container.encode(1, forKey: .a)
        try container.encode(2, forKey: .b)
    }
}

/// Opens the same nested container twice; only the second should survive.
private struct RepeatedNestedKey: Encodable {
    enum CodingKeys: String, CodingKey { case inner }
    enum InnerKeys: String, CodingKey { case x }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var first = container.nestedContainer(keyedBy: InnerKeys.self, forKey: .inner)
        try first.encode(1, forKey: .x)
        var second = container.nestedContainer(keyedBy: InnerKeys.self, forKey: .inner)
        try second.encode(2, forKey: .x)
    }
}

private struct Inner: Decodable { var x: Int }
private struct Outer: Decodable { var inner: Inner }
private struct Listed: Decodable { var items: [Inner] }

/// Records the coding path it was decoded at.
private struct PathRecorder: Decodable {
    var path: [String]
    init(from decoder: any Decoder) throws {
        path = decoder.codingPath.map(\.stringValue)
    }
}
private struct RecorderHolder: Decodable { var list: [PathRecorder] }

private struct EncodingPathRecorder: Encodable {
    let expected: [String]

    func encode(to encoder: any Encoder) throws {
        #expect(encoder.codingPath.map(\.stringValue) == expected)
        var container = encoder.singleValueContainer()
        #expect(container.codingPath.map(\.stringValue) == expected)
        try container.encode(1)
    }
}

private struct ManualEncodingPaths: Encodable {
    enum Keys: String, CodingKey { case list, parent }

    func encode(to encoder: any Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)
        var list = keyed.nestedUnkeyedContainer(forKey: .list)
        #expect(list.codingPath.map(\.stringValue) == ["list"])

        let nestedKeyed = list.nestedContainer(keyedBy: Keys.self)
        #expect(nestedKeyed.codingPath.map(\.stringValue) == ["list", "Index 0"])

        let nestedUnkeyed = list.nestedUnkeyedContainer()
        #expect(nestedUnkeyed.codingPath.map(\.stringValue) == ["list", "Index 1"])

        let arraySuper = list.superEncoder()
        #expect(arraySuper.codingPath.map(\.stringValue) == ["list", "Index 2"])

        let keyedSuper = keyed.superEncoder()
        #expect(keyedSuper.codingPath.map(\.stringValue) == ["super"])

        let keyedSuperForKey = keyed.superEncoder(forKey: .parent)
        #expect(keyedSuperForKey.codingPath.map(\.stringValue) == ["parent"])
    }
}

private struct NumericCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct NumericKeyProbe: Decodable {
    let keys: [String]
    let value: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: NumericCodingKey.self)
        keys = container.allKeys.map(\.stringValue)
        value = try container.decode(Int.self, forKey: NumericCodingKey(intValue: 1)!)
    }
}

/// Reads one more element than the array holds.
private struct ReadsPastEnd: Decodable {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try container.decode(Int.self)
        _ = try container.decode(Int.self)
    }
}

/// A COSE-style key: integer map keys, as in WebAuthn credential public keys.
private struct COSEKey: Decodable, Equatable {
    var kty: Int
    var alg: Int
    var crv: Int?
    enum CodingKeys: Int, CodingKey { case kty = 1, alg = 3, crv = -1 }
}

private func codingPath(of error: any Error) -> [String]? {
    switch error {
    case DecodingError.typeMismatch(_, let context),
         DecodingError.valueNotFound(_, let context),
         DecodingError.keyNotFound(_, let context),
         DecodingError.dataCorrupted(let context):
        return context.codingPath.map(\.stringValue)
    default:
        return nil
    }
}

private func decodingError(_ body: () throws -> Void) -> (any Error)? {
    do { try body(); return nil } catch { return error }
}

// MARK: - Tests

@Suite("Codable correctness")
struct CodableCorrectnessTests {
    // MARK: Repeated keys

    @Test("a key encoded twice keeps its last value")
    func repeatedKeyLastWriteWins() throws {
        let bytes = try CBOREncoder().encode(RepeatedKey())
        // Exactly one entry per key: decoding rejects a duplicate by default.
        let decoded = try CBOR.decode(bytes)
        #expect(decoded == ["a": 1, "b": 2])
        #expect(hexString(bytes) == "a2616101616202") // {"a": 1, "b": 2}, sorted
    }

    @Test("a nested container opened twice keeps the last one")
    func repeatedNestedContainer() throws {
        let bytes = try CBOREncoder().encode(RepeatedNestedKey())
        let decoded = try CBOR.decode(bytes)
        #expect(decoded == ["inner": ["x": 2]])
    }

    // MARK: Coding paths

    @Test("a type mismatch in a nested struct reports the full path")
    func nestedKeyedPath() {
        let bytes = (["inner": ["x": "not an int"]] as CBOR).encode()
        let error = decodingError { _ = try CBORDecoder().decode(Outer.self, from: bytes) }
        #expect(codingPath(of: error!) == ["inner", "x"])
    }

    @Test("a type mismatch inside an array reports the index")
    func nestedUnkeyedPath() {
        let bytes = (["items": [["x": 1], ["x": "bad"]]] as CBOR).encode()
        let error = decodingError { _ = try CBORDecoder().decode(Listed.self, from: bytes) }
        #expect(codingPath(of: error!) == ["items", "Index 1", "x"])
    }

    @Test("a scalar mismatch in an array reports the index")
    func unkeyedScalarPath() {
        let bytes = ([1, "two", 3] as CBOR).encode()
        let error = decodingError { _ = try CBORDecoder().decode([Int].self, from: bytes) }
        #expect(codingPath(of: error!) == ["Index 1"])
    }

    @Test("a missing key reports the path of its container")
    func missingKeyPath() {
        let bytes = (["inner": ["y": 1]] as CBOR).encode()
        let error = decodingError { _ = try CBORDecoder().decode(Outer.self, from: bytes) }
        #expect(codingPath(of: error!) == ["inner"])
    }

    @Test("reading past the end of an array reports the missing index")
    func pastEndPath() {
        let bytes = ([7] as CBOR).encode()
        let error = decodingError { _ = try CBORDecoder().decode(ReadsPastEnd.self, from: bytes) }
        #expect(codingPath(of: error!) == ["Index 1"])
    }

    @Test("a nested decoder exposes its path to user code")
    func pathVisibleToDecodable() throws {
        let bytes = (["list": [[:] as CBOR, [:] as CBOR]] as CBOR).encode()
        let holder = try CBORDecoder().decode(RecorderHolder.self, from: bytes)
        #expect(holder.list.map(\.path) == [["list", "Index 0"], ["list", "Index 1"]])
    }

    @Test("encoded array elements expose their index in codingPath")
    func encodedArrayPaths() throws {
        let values = [
            EncodingPathRecorder(expected: ["Index 0"]),
            EncodingPathRecorder(expected: ["Index 1"]),
        ]
        _ = try CBOREncoder().encode(values)
        _ = try CBOREncoder().encode(["list": [
            EncodingPathRecorder(expected: ["list", "Index 0"]),
            EncodingPathRecorder(expected: ["list", "Index 1"]),
        ]])
    }

    @Test("manual nested containers and super encoders expose the complete path")
    func manualEncodingPaths() throws {
        _ = try CBOREncoder().encode(ManualEncodingPaths())
    }

    // MARK: Integer keys

    @Test("Int-valued coding keys decode an integer-keyed map")
    func integerKeys() throws {
        let bytes = ([1: 2, 3: -7, -1: 1] as CBOR).encode()
        #expect(try CBORDecoder().decode(COSEKey.self, from: bytes) == COSEKey(kty: 2, alg: -7, crv: 1))
    }

    @Test("an absent integer key is still absent")
    func absentIntegerKey() throws {
        let bytes = ([1: 2, 3: -7] as CBOR).encode()
        #expect(try CBORDecoder().decode(COSEKey.self, from: bytes).crv == nil)
    }

    @Test("a text key takes precedence over its integer form")
    func textKeyWins() throws {
        let bytes = (["kty": 9, 1: 2, 3: -7] as CBOR).encode()
        #expect(try CBORDecoder().decode(COSEKey.self, from: bytes).kty == 9)
    }

    @Test("a dictionary with Int keys decodes an integer-keyed map, negatives included")
    func integerKeyedDictionary() throws {
        let bytes = ([1: "a", -2: "b"] as CBOR).encode()
        #expect(try CBORDecoder().decode([Int: String].self, from: bytes) == [1: "a", -2: "b"])
    }

    @Test("Codable writes integer dictionary keys as text")
    func integerDictionaryEncoding() throws {
        let bytes = try CBOREncoder().encode([1: "a"])
        #expect(try CBOR.decode(bytes) == ["1": "a"])
    }

    @Test("allKeys deduplicates integer and text keys with text precedence")
    func allKeysDeduplicatesNumericKeys() throws {
        let bytes = (CBOR.map([.unsignedInt(1): 2, .textString("1"): 9])).encode()
        let decoded = try CBORDecoder().decode(NumericKeyProbe.self, from: bytes)
        #expect(decoded.keys == ["1"])
        #expect(decoded.value == 9)
    }

    // MARK: Slices

    @Test("decoding from a slice that does not start at zero")
    func offsetSlice() throws {
        let bytes: [UInt8] = [0xff, 0xff] + (["x": 5] as CBOR).encode()
        #expect(try CBORDecoder().decode(Inner.self, from: bytes[2...]).x == 5)
    }
}
