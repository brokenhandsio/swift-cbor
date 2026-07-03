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
        let options = CBOROptions(maximumDepth: 2)
        #expect(throws: CBORError.maxDepthExceeded(2)) {
            try CBOR.decode(bytes(fromHex: "81818100"), options: options)
        }
        // At the limit it succeeds.
        #expect(throws: Never.self) {
            _ = try CBOR.decode(bytes(fromHex: "818100"), options: CBOROptions(maximumDepth: 2))
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

    @Test("duplicate map keys are rejected when requested")
    func duplicateKeys() {
        // {1: 2, 1: 3}
        let input = bytes(fromHex: "a201020103")
        #expect(throws: CBORError.duplicateMapKey) {
            try CBOR.decode(input, options: CBOROptions(rejectDuplicateMapKeys: true))
        }
    }
}
