import Testing
import CBOR

@Suite("Malformed input")
struct MalformedInputTests {
    @Test("empty input")
    func empty() {
        #expect(throws: CBORError.unexpectedEnd(offset: 0)) {
            try CBOR.decode([UInt8]())
        }
    }

    @Test("truncated integer argument")
    func truncatedInteger() {
        #expect(throws: CBORError.unexpectedEnd(offset: 0)) {
            try CBOR.decode(bytes(fromHex: "18")) // 0x18 promises a 1-byte argument
        }
        #expect(throws: CBORError.unexpectedEnd(offset: 0)) {
            try CBOR.decode(bytes(fromHex: "1901")) // 0x19 promises a 2-byte argument
        }
    }

    @Test("truncated byte string")
    func truncatedByteString() {
        #expect(throws: CBORError.unexpectedEnd(offset: 0)) {
            try CBOR.decode(bytes(fromHex: "4201")) // len 2, only 1 byte present
        }
    }

    @Test("invalid UTF-8 in text string")
    func invalidUTF8() {
        #expect(throws: CBORError.invalidUTF8(offset: 0)) {
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
        // The offset is the bad chunk's, not the string's.
        #expect(throws: CBORError.invalidIndefiniteLength(offset: 1)) {
            try CBOR.decode(bytes(fromHex: "5f00ff")) // chunk 0x00 is an integer, not a byte string
        }
    }

    @Test("depth limit is enforced")
    func depthLimit() {
        // [[[0]]] is depth 3; allow only 2.
        let options = CBORDecodingOptions(maximumDepth: 2)
        #expect(throws: CBORError.maxDepthExceeded(limit: 2, offset: 3)) {
            try CBOR.decode(bytes(fromHex: "81818100"), options: options)
        }
        // At the limit it succeeds.
        #expect(throws: Never.self) {
            _ = try CBOR.decode(bytes(fromHex: "818100"), options: CBORDecodingOptions(maximumDepth: 2))
        }
    }

    @Test("strict decode rejects trailing data")
    func trailingData() {
        #expect(throws: CBORError.trailingData(remaining: 1, offset: 1)) {
            try CBOR.decode(bytes(fromHex: "0000"))
        }
    }

    @Test("decodeFirst accepts and reports trailing data")
    func decodeFirstReportsRemainder() throws {
        let (value, consumed) = try CBOR.decodeFirst(bytes(fromHex: "0000"))
        #expect(value == 0)
        #expect(consumed == 1)
    }

    @Test("duplicate map keys are rejected by default, at the repeated key", arguments: [
        ("a201020103", 3),       // {1: 2, 1: 3}
        ("bf01020103ff", 3),     // the same, as an indefinite-length map
        ("a20102180103", 3),     // {1: 2, 1: 3} with the second 1 in a non-shortest form
        ("a2616101616102", 4),   // {"a": 1, "a": 2}
        ("81a201020103", 4),     // a duplicate inside a nested map
        ("a2810102810103", 4),   // {[1]: 2, [1]: 3}: a container key, at its head
    ])
    func duplicateKeys(hex: String, offset: Int) {
        #expect(throws: CBORError.duplicateMapKey(offset: offset)) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }

    @Test("duplicate map keys are accepted when allowed, and the last value wins")
    func duplicateKeysAllowed() throws {
        let options = CBORDecodingOptions(rejectDuplicateMapKeys: false)
        #expect(try CBOR.decode(bytes(fromHex: "a201020103"), options: options) == [1: 3])
        #expect(try CBOR.decode(bytes(fromHex: "bf01020103ff"), options: options) == [1: 3])
    }

    @Test("integer and float keys remain distinct")
    func distinctFloatKeys() throws {
        // {1: 1, 1.0: 2}.
        #expect(try CBOR.decode(bytes(fromHex: "a20101f93c0002")).mapValue?.count == 2)
    }

    @Test("large declared counts in nested truncated containers throw")
    func nestedDeclaredCounts() {
        // Each map declares 1024 pairs but only supplies a key and another map.
        // This small input previously reserved 1024 dictionary slots per frame.
        let mapHead: [UInt8] = [0xb9, 0x04, 0x00, 0x00]
        let maps = Array(repeating: mapHead, count: 512).flatMap { $0 }
        #expect(throws: CBORError.unexpectedEnd(offset: maps.count)) {
            try CBOR.decode(maps)
        }

        let arrayHead: [UInt8] = [0x99, 0x04, 0x00]
        let arrays = Array(repeating: arrayHead, count: 512).flatMap { $0 }
        #expect(throws: CBORError.unexpectedEnd(offset: arrays.count)) {
            try CBOR.decode(arrays)
        }
    }

    @Test("the Codable decoder rejects duplicate keys by default")
    func codableDuplicateKeys() throws {
        struct Point: Decodable { var x: Int }
        // {"x": 1, "x": 2}
        let input = bytes(fromHex: "a2617801617802")
        #expect(throws: CBORError.duplicateMapKey(offset: 4)) {
            try CBORDecoder().decode(Point.self, from: input)
        }
        let lenient = CBORDecoder(options: CBORDecodingOptions(rejectDuplicateMapKeys: false))
        #expect(try lenient.decode(Point.self, from: input).x == 2)
    }
}
