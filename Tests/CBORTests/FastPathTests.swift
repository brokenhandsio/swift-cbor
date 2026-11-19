import Testing
import CBOR

/// Inputs exercising each way a string's bytes are copied out of the input.
private let stringInputs: [(hex: String, value: CBOR)] = [
    ("4401020304", .byteString([1, 2, 3, 4])),                         // definite bytes
    ("40", .byteString([])),                                            // empty bytes
    ("5f42010243030405ff", .byteString([1, 2, 3, 4, 5])),               // chunked bytes
    ("6449455446", "IETF"),                                             // definite text
    ("7f657374726561646d696e67ff", "streaming"),                        // chunked text
    ("82430a0b0c63616263", [.byteString([0x0a, 0x0b, 0x0c]), "abc"]),   // nested
    ("590100" + String(repeating: "ab", count: 256), .byteString(Array(repeating: 0xab, count: 256))),
]

@Suite("Decoding from a Span, an array and a slice")
struct DecodeSourceTests {
    @Test("a bare Span, an array and an offset slice decode the same", arguments: stringInputs)
    func sameResult(hex: String, value: CBOR) throws {
        let input = bytes(fromHex: hex)
        // A slice that does not start at index 0, so positions in its span differ
        // from indices in its array.
        let padded: [UInt8] = [0xee, 0xee, 0xee] + input + [0xee]
        let slice = padded[3..<(3 + input.count)]

        let rest = padded[3...]
        // Spans can't escape into `#expect`'s closure, so decode from them first.
        let fromSpan = try CBOR.decode(slice.span)
        let firstFromSpan = try CBOR.decodeFirst(rest.span).value

        #expect(try CBOR.decode(input) == value)
        #expect(try CBOR.decode(slice) == value)
        #expect(fromSpan == value)
        #expect(try CBOR.decodeFirst(rest).value == value)
        #expect(firstFromSpan == value)
    }

    @Test("a string ending exactly at the end of an offset slice decodes")
    func stringAtSliceEnd() throws {
        let padded: [UInt8] = [0x00, 0x43, 0x01, 0x02, 0x03, 0xff]
        #expect(try CBOR.decode(padded[1..<5]) == .byteString([1, 2, 3]))
    }

    @Test("a string running past the end of a slice is truncated, not read beyond it")
    func stringPastSliceEnd() {
        // The array holds the third byte, but the slice stops before it.
        let padded: [UInt8] = [0x43, 0x01, 0x02, 0x03]
        #expect(throws: CBORError.unexpectedEnd(offset: 0)) {
            try CBOR.decode(padded[0..<3])
        }
    }
}

private let tagCases: [(CBOR, String)] = [
    (.tagged(1, 1_363_896_240), "c11a514b67b0"),
    (.tagged(24, .tagged(1, 0)), "d818c100"),                           // nested tags
    (.array([.tagged(1, 0), 2]), "82c10002"),                           // a tag in an array
    (.array([.tagged(1, .array([1, 2])), 3]), "82c182010203"),          // a tag around an array, in an array
    (.map(["a": .tagged(2, .byteString([1]))]), "a16161c24101"),        // a tag as a map value
    (.map([.tagged(1, 0): 5]), "a1c10005"),                             // a tag as a map key
    (.tagged(18, .array([.byteString([]), .map([:])])), "d28240a0"),     // COSE_Sign1-shaped
]

@Suite("Encoding tags")
struct TagEncodingTests {
    @Test("tags encode to exact bytes wherever they appear", arguments: tagCases)
    func exactBytes(value: CBOR, hex: String) throws {
        #expect(hexString(value.encode()) == hex)
        #expect(try CBOR.decode(value.encode()) == value)
    }

    @Test("deeply nested tags encode without recursion")
    func deepTags() throws {
        var value: CBOR = 0
        for _ in 0..<1000 { value = .tagged(1, value) }
        let encoded = value.encode()
        #expect(encoded.count == 1001)
        #expect(encoded.prefix(1000).allSatisfy { $0 == 0xc1 })
        #expect(try CBOR.decode(encoded, options: CBORDecodingOptions(maximumDepth: 1000)) == value)
    }
}
