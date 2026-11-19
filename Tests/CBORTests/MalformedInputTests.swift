import Testing
import CBOR

@Suite("Malformed input")
struct MalformedInputTests {
    @Test("empty input")
    func empty() {
        #expect(throws: CBORError.unexpectedEnd) {
            try CBOR.decode([UInt8]())
        }
    }

    @Test("truncated integer argument")
    func truncatedInteger() {
        #expect(throws: CBORError.unexpectedEnd) {
            try CBOR.decode(bytes(fromHex: "18")) // 0x18 promises a 1-byte argument
        }
        #expect(throws: CBORError.unexpectedEnd) {
            try CBOR.decode(bytes(fromHex: "1901")) // 0x19 promises a 2-byte argument
        }
    }

    @Test("truncated byte string")
    func truncatedByteString() {
        #expect(throws: CBORError.unexpectedEnd) {
            try CBOR.decode(bytes(fromHex: "4201")) // len 2, only 1 byte present
        }
    }

    @Test("invalid UTF-8 in text string")
    func invalidUTF8() {
        #expect(throws: CBORError.invalidUTF8) {
            try CBOR.decode(bytes(fromHex: "62ffff")) // text len 2, invalid bytes
        }
    }

    @Test("reserved additional information 28/29/30", arguments: [
        "1c", "1d", "1e", "3c", "5c", "7c", "9c", "bc", "dc", "fc",
    ])
    func reservedAdditionalInfo(_ hex: String) {
        #expect(throws: (any Error).self) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }

    @Test("lone break stop code")
    func loneBreak() {
        #expect(throws: (any Error).self) {
            try CBOR.decode(bytes(fromHex: "ff"))
        }
    }

    @Test("break inside definite-length array")
    func breakInDefinite() {
        #expect(throws: (any Error).self) {
            try CBOR.decode(bytes(fromHex: "8fff")) // definite array len 15, then break
        }
    }

    @Test("indefinite byte string with a non-byte-string chunk")
    func badIndefiniteChunk() {
        #expect(throws: CBORError.invalidIndefiniteLength) {
            try CBOR.decode(bytes(fromHex: "5f00ff")) // chunk 0x00 is an integer, not a byte string
        }
    }

    @Test("depth limit is enforced")
    func depthLimit() {
        // [[[0]]] is depth 3; allow only 2.
        let options = CBORDecodingOptions(maximumDepth: 2)
        #expect(throws: CBORError.maxDepthExceeded(2)) {
            try CBOR.decode(bytes(fromHex: "81818100"), options: options)
        }
        // At the limit it succeeds.
        #expect(throws: Never.self) {
            _ = try CBOR.decode(bytes(fromHex: "818100"), options: CBORDecodingOptions(maximumDepth: 2))
        }
    }

    @Test("strict decode rejects trailing data")
    func trailingData() {
        #expect(throws: CBORError.trailingData(remaining: 1)) {
            try CBOR.decode(bytes(fromHex: "0000"))
        }
    }

    @Test("decodeFirst accepts and reports trailing data")
    func decodeFirstReportsRemainder() throws {
        let (value, consumed) = try CBOR.decodeFirst(bytes(fromHex: "0000"))
        #expect(value == 0)
        #expect(consumed == 1)
    }

    @Test("duplicate map keys are rejected by default", arguments: [
        "a201020103",       // {1: 2, 1: 3}
        "bf01020103ff",     // the same, as an indefinite-length map
        "a20102180103",     // {1: 2, 1: 3} with the second 1 in a non-shortest form
        "a2616101616102",   // {"a": 1, "a": 2}
        "81a201020103",     // a duplicate inside a nested map
    ])
    func duplicateKeys(hex: String) {
        #expect(throws: CBORError.duplicateMapKey) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }

    @Test("duplicate map keys are accepted when allowed, and the last value wins")
    func duplicateKeysAllowed() throws {
        let options = CBORDecodingOptions(rejectDuplicateMapKeys: false)
        #expect(try CBOR.decode(bytes(fromHex: "a201020103"), options: options) == [1: 3])
        #expect(try CBOR.decode(bytes(fromHex: "bf01020103ff"), options: options) == [1: 3])
    }

    @Test("keys that differ only in float sign or type are not duplicates")
    func distinctFloatKeys() throws {
        // {0.0: 1, -0.0: 2} as halves, then {1: 1, 1.0: 2}.
        #expect(try CBOR.decode(bytes(fromHex: "a2f9000001f9800002")).mapValue?.count == 2)
        #expect(try CBOR.decode(bytes(fromHex: "a20101f93c0002")).mapValue?.count == 2)
    }

    @Test("the Codable decoder rejects duplicate keys by default")
    func codableDuplicateKeys() throws {
        struct Point: Decodable { var x: Int }
        // {"x": 1, "x": 2}
        let input = bytes(fromHex: "a2617801617802")
        #expect(throws: CBORError.duplicateMapKey) {
            try CBORDecoder().decode(Point.self, from: input)
        }
        let lenient = CBORDecoder(options: CBORDecodingOptions(rejectDuplicateMapKeys: false))
        #expect(try lenient.decode(Point.self, from: input).x == 2)
    }
}
