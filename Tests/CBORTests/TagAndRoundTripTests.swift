import Testing
import CBOR

@Suite("Tags")
struct TagTests {
    @Test("tag wraps and unwraps its value")
    func basicTag() throws {
        let value: CBOR = .tagged(.uri, .textString("https://example.com"))
        let decoded = try CBOR.decode(value.encode())
        #expect(decoded == value)
        guard case .tagged(let tag, let inner) = decoded else {
            Issue.record("expected .tagged")
            return
        }
        #expect(tag == .uri)
        #expect(inner == .textString("https://example.com"))
    }

    @Test("nested tags")
    func nestedTags() throws {
        let value: CBOR = .tagged(CBORTag(100), .tagged(CBORTag(200), .unsignedInt(5)))
        #expect(try CBOR.decode(value.encode()) == value)
    }

    @Test("positive bignum decodes as tagged byte string")
    func positiveBignum() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "c249010000000000000000"))
        #expect(decoded == .tagged(.positiveBignum, .byteString([0x01, 0, 0, 0, 0, 0, 0, 0, 0])))
    }

    @Test("encoded-CBOR-data tag (24) holds a byte string of CBOR")
    func encodedCBORData() throws {
        // Tag 24 wrapping the encoding of the array [1, 2].
        let inner = CBOR.array([1, 2]).encode()
        let value: CBOR = .tagged(.encodedCBORData, .byteString(inner))
        #expect(try CBOR.decode(value.encode()) == value)
    }
}

@Suite("Round trip")
struct RoundTripTests {
    static let values: [CBOR] = [
        .unsignedInt(0),
        .unsignedInt(.max),
        .negativeInt(0),
        .negativeInt(.max),
        .byteString([]),
        .byteString([0xde, 0xad, 0xbe, 0xef]),
        .textString(""),
        .textString("hello, 世界 🌍"),
        .array([]),
        [1, "two", [3, 4], ["k": "v"]],
        [:],
        ["nested": ["a": [1, 2, 3], "b": .null]],
        .bool(true),
        .bool(false),
        .null,
        .undefined,
        .simple(0),
        .simple(19),
        .simple(32),
        .simple(255),
        .half(3.5),
        .float(2.5),
        .double(2.5),
        .tagged(.epochDateTime, .unsignedInt(1000)),
    ]

    @Test("encode then decode is identity", arguments: values)
    func roundTrip(_ value: CBOR) throws {
        let decoded = try CBOR.decode(value.encode())
        #expect(decoded == value)
    }

    @Test("encoding is idempotent through a decode", arguments: values)
    func encodingStable(_ value: CBOR) throws {
        let once = value.encode()
        let twice = try CBOR.decode(once).encode()
        #expect(once == twice)
    }
}
