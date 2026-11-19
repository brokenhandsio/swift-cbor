import Testing
import CBOR

@Suite("Diagnostic notation")
struct DescriptionTests {
    @Test("integers print in decimal across the whole range", arguments: [
        (CBOR.unsignedInt(0), "0"),
        (.unsignedInt(1_000_000), "1000000"),
        (.unsignedInt(.max), "18446744073709551615"),
        (-1, "-1"),
        (-1000, "-1000"),
        (.negativeInt(.max), "-18446744073709551616"),
    ])
    func integers(value: CBOR, expected: String) {
        #expect(value.description == expected)
    }

    @Test("byte strings print as lowercase hex")
    func byteStrings() {
        #expect(CBOR.byteString([]).description == "h''")
        #expect(CBOR.byteString([0x01, 0xab, 0xff]).description == "h'01abff'")
    }

    @Test("text strings print quoted, with JSON escapes", arguments: [
        (CBOR.textString(""), #""""#),
        ("IETF", #""IETF""#),
        ("ü水", #""ü水""#),
        ("a\"b\\c", #""a\"b\\c""#),
        ("\n\r\t\u{08}\u{0C}", #""\n\r\t\b\f""#),
        ("\u{00}\u{1F}", #""\u0000\u001f""#),
    ])
    func textStrings(value: CBOR, expected: String) {
        #expect(value.description == expected)
    }

    @Test("floats print the shortest round-tripping decimal", arguments: [
        (CBOR.double(1.5), "1.5"),
        (.double(1), "1.0"),
        (.double(-0.0), "-0.0"),
        (.double(1.1), "1.1"),
        (.double(1e300), "1e+300"),
        (.double(.nan), "NaN"),
        (.double(.infinity), "Infinity"),
        (.double(-.infinity), "-Infinity"),
    ])
    func doubles(value: CBOR, expected: String) {
        #expect(value.description == expected)
    }

    @Test("half and single precision carry their encoding indicator", arguments: [
        (CBOR.half(bitPattern: 0x3e00), "1.5_1"),
        (.half(bitPattern: 0x7bff), "65504.0_1"),
        (.half(bitPattern: 0x7c00), "Infinity_1"),
        (.half(bitPattern: 0x7e00), "NaN_1"),
        (.float(1.5), "1.5_2"),
        (.float(0.1), "0.1_2"),
        (.float(100_000), "100000.0_2"),
    ])
    func narrowFloats(value: CBOR, expected: String) {
        #expect(value.description == expected)
    }

    @Test("the same number in different float widths prints differently")
    func widthsAreDistinct() {
        let widths: [CBOR] = [.half(bitPattern: 0x3e00), .float(1.5), .double(1.5)]
        #expect(Set(widths.map(\.description)).count == 3)
    }

    @Test("simple values and the special values", arguments: [
        (CBOR.simple(16), "simple(16)"),
        (.simple(255), "simple(255)"),
        (true, "true"),
        (false, "false"),
        (nil, "null"),
        (.undefined, "undefined"),
    ])
    func simpleValues(value: CBOR, expected: String) {
        #expect(value.description == expected)
    }

    @Test("containers and tags", arguments: [
        (CBOR.array([]), "[]"),
        ([1, [2, 3], [4, 5]] as CBOR, "[1, [2, 3], [4, 5]]"),
        (.map([:]), "{}"),
        (["a": 1, "b": [2, 3]] as CBOR, #"{"a": 1, "b": [2, 3]}"#),
        (.tagged(.epochDateTime, 1_363_896_240), "1(1363896240)"),
        (.tagged(24, .byteString([0x64])), "24(h'64')"),
        ([.tagged(1, [1, 2])] as CBOR, "[1([1, 2])]"),
    ])
    func containers(value: CBOR, expected: String) {
        #expect(value.description == expected)
    }

    @Test("map entries print in encoded key order, whatever order they were added in")
    func mapOrder() {
        // 1 encodes as 01, 10 as 0a, -1 as 20, "a" as 6161 and [0] as 8100.
        let map: CBOR = [[0]: 5, "a": 4, -1: 3, 10: 2, 1: 1]
        #expect(map.description == #"{1: 1, 10: 2, -1: 3, "a": 4, [0]: 5}"#)
    }

    @Test("string interpolation and print use the diagnostic notation")
    func interpolation() {
        let value: CBOR = [1, "two"]
        #expect("\(value)" == #"[1, "two"]"#)
        #expect(String(describing: value) == #"[1, "two"]"#)
    }

    @Test("printing a value nested as deeply as decoding allows")
    func deepNesting() throws {
        let depth = CBORDecodingOptions.maximumSupportedDepth
        let bytes = [UInt8](repeating: 0x81, count: depth) + [0x00]
        let value = try CBOR.decode(bytes, options: CBORDecodingOptions(maximumDepth: depth))
        let expected = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
        #expect(value.description == expected)
    }

    @Test("Codable type mismatches name the kind of item, not its contents")
    func typeMismatchMessage() {
        let error = #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(Int.self, from: bytes(fromHex: "6449455446")) // "IETF"
        }
        guard case .typeMismatch(_, let context)? = error else {
            Issue.record("expected a type mismatch, got \(String(describing: error))")
            return
        }
        #expect(context.debugDescription == "Expected to decode Int but found a text string instead.")
    }
}
