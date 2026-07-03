import CBOR

// The examples from RFC 8949 Appendix A. NaN examples are covered separately in
// FloatTests (NaN != NaN makes value equality unsuitable for a table check).
enum RFCVectors {
    static let all: [RFCVector] = integers + floats + simpleValues + tags + strings + arrays + maps + indefinite

    // MARK: Unsigned & negative integers

    static let integers: [RFCVector] = [
        RFCVector("00", 0),
        RFCVector("01", 1),
        RFCVector("0a", 10),
        RFCVector("17", 23),
        RFCVector("1818", 24),
        RFCVector("1819", 25),
        RFCVector("1864", 100),
        RFCVector("1903e8", 1000),
        RFCVector("1a000f4240", 1_000_000),
        RFCVector("1b000000e8d4a51000", 1_000_000_000_000),
        RFCVector("1bffffffffffffffff", .unsignedInt(18446744073709551615)),
        RFCVector("c249010000000000000000", .tagged(.positiveBignum, .byteString([0x01, 0, 0, 0, 0, 0, 0, 0, 0]))),
        RFCVector("3bffffffffffffffff", .negativeInt(18446744073709551615)),
        RFCVector("c349010000000000000000", .tagged(.negativeBignum, .byteString([0x01, 0, 0, 0, 0, 0, 0, 0, 0]))),
        RFCVector("20", -1),
        RFCVector("29", -10),
        RFCVector("3863", -100),
        RFCVector("3903e7", -1000),
    ]

    // MARK: Floating-point (excluding NaN — see FloatTests)

    static let floats: [RFCVector] = [
        RFCVector("f90000", .half(0.0)),
        RFCVector("f98000", .half(-0.0)),
        RFCVector("f93c00", .half(1.0)),
        RFCVector("fb3ff199999999999a", .double(1.1)),
        RFCVector("f93e00", .half(1.5)),
        RFCVector("f97bff", .half(65504.0)),
        RFCVector("fa47c35000", .float(100000.0)),
        RFCVector("fa7f7fffff", .float(3.4028234663852886e+38)),
        RFCVector("fb7e37e43c8800759c", .double(1.0e+300)),
        RFCVector("f90001", .half(5.960464477539063e-8)),
        RFCVector("f90400", .half(0.00006103515625)),
        RFCVector("f9c400", .half(-4.0)),
        RFCVector("fbc010666666666666", .double(-4.1)),
        RFCVector("f97c00", .half(.infinity)),
        RFCVector("f9fc00", .half(-.infinity)),
        RFCVector("fa7f800000", .float(.infinity)),
        RFCVector("faff800000", .float(-.infinity)),
        RFCVector("fb7ff0000000000000", .double(.infinity)),
        RFCVector("fbfff0000000000000", .double(-.infinity)),
    ]

    // MARK: Simple values

    static let simpleValues: [RFCVector] = [
        RFCVector("f4", .bool(false)),
        RFCVector("f5", .bool(true)),
        RFCVector("f6", .null),
        RFCVector("f7", .undefined),
        RFCVector("f0", .simple(16)),
        RFCVector("f8ff", .simple(255)),
    ]

    // MARK: Tags

    static let tags: [RFCVector] = [
        RFCVector("c074323031332d30332d32315432303a30343a30305a",
                  .tagged(.standardDateTimeString, .textString("2013-03-21T20:04:00Z"))),
        RFCVector("c11a514b67b0", .tagged(.epochDateTime, .unsignedInt(1363896240))),
        RFCVector("c1fb41d452d9ec200000", .tagged(.epochDateTime, .double(1363896240.5))),
        RFCVector("d74401020304", .tagged(.expectedBase16, .byteString([0x01, 0x02, 0x03, 0x04]))),
        RFCVector("d818456449455446", .tagged(.encodedCBORData, .byteString([0x64, 0x49, 0x45, 0x54, 0x46]))),
        RFCVector("d82076687474703a2f2f7777772e6578616d706c652e636f6d",
                  .tagged(.uri, .textString("http://www.example.com"))),
    ]

    // MARK: Byte & text strings

    static let strings: [RFCVector] = [
        RFCVector("40", .byteString([])),
        RFCVector("4401020304", .byteString([0x01, 0x02, 0x03, 0x04])),
        RFCVector("60", .textString("")),
        RFCVector("6161", .textString("a")),
        RFCVector("6449455446", .textString("IETF")),
        RFCVector("62225c", .textString("\"\\")),
        RFCVector("62c3bc", .textString("\u{00fc}")),      // "ü"
        RFCVector("63e6b0b4", .textString("\u{6c34}")),    // "水"
        RFCVector("64f0908591", .textString("\u{10151}")), // "𐅑"
    ]

    // MARK: Arrays

    static let arrays: [RFCVector] = [
        RFCVector("80", .array([])),
        RFCVector("83010203", [1, 2, 3]),
        RFCVector("8301820203820405", [1, [2, 3], [4, 5]]),
        RFCVector("98190102030405060708090a0b0c0d0e0f101112131415161718181819",
                  .array((1...25).map { .unsignedInt(UInt64($0)) })),
    ]

    // MARK: Maps

    static let maps: [RFCVector] = [
        RFCVector("a0", [:]),
        RFCVector("a201020304", [1: 2, 3: 4]),
        RFCVector("a26161016162820203", ["a": 1, "b": [2, 3]]),
        RFCVector("826161a161626163", ["a", ["b": "c"]]),
        RFCVector("a56161614161626142616361436164614461656145",
                  ["a": "A", "b": "B", "c": "C", "d": "D", "e": "E"]),
    ]

    // MARK: Indefinite-length (decoded, but re-encoded in definite form)

    static let indefinite: [RFCVector] = [
        RFCVector("5f42010243030405ff", .byteString([0x01, 0x02, 0x03, 0x04, 0x05]), encodes: false),
        RFCVector("7f657374726561646d696e67ff", .textString("streaming"), encodes: false),
        RFCVector("9fff", .array([]), encodes: false),
        RFCVector("9f018202039f0405ffff", [1, [2, 3], [4, 5]], encodes: false),
        RFCVector("9f01820203820405ff", [1, [2, 3], [4, 5]], encodes: false),
        RFCVector("83018202039f0405ff", [1, [2, 3], [4, 5]], encodes: false),
        RFCVector("83019f0203ff820405", [1, [2, 3], [4, 5]], encodes: false),
        RFCVector("9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff",
                  .array((1...25).map { .unsignedInt(UInt64($0)) }), encodes: false),
        RFCVector("bf61610161629f0203ffff", ["a": 1, "b": [2, 3]], encodes: false),
        RFCVector("826161bf61626163ff", ["a", ["b": "c"]], encodes: false),
        RFCVector("bf6346756ef563416d7421ff", ["Fun": true, "Amt": -2], encodes: false),
    ]
}
