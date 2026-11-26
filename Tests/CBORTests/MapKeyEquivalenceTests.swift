import Testing
import CBOR

@Suite("RFC 8949 map key equivalence")
struct MapKeyEquivalenceTests {
    @Test("canonically equivalent Unicode strings retain distinct UTF-8 keys")
    func distinctUTF8() throws {
        // {"é": 0, "e◌́": 1}; Swift String == considers these equal.
        let bytes = bytes(fromHex: "a262c3a9006365cc8101")
        let decoded = try CBOR.decode(bytes)
        guard case .map(let map) = decoded else {
            Issue.record("expected a map")
            return
        }
        let composed = CBOR.textString("\u{00e9}")
        let decomposed = CBOR.textString("e\u{0301}")
        #expect(composed != decomposed)
        #expect(map.count == 2)
        #expect(map[composed] == 0)
        #expect(map[decomposed] == 1)
        #expect(try CBOR.decode(decoded.encode()) == decoded)
    }

    @Test("equal numeric floats are duplicate keys across widths and signed zero")
    func equivalentFloats() {
        for hex in [
            "a2f9000000f9800001",       // +0 and -0, both half
            "a2f93e0000fa3fc0000001", // 1.5 in half and single precision
            "a2f93e0000fb3ff800000000000001", // 1.5 in half and double
            "a2f97e0000fa7fc0000001", // NaNs with the same significand
        ] {
            #expect(throws: CBORError.duplicateMapKey(offset: 5)) {
                try CBOR.decode(bytes(fromHex: hex))
            }
        }
    }

    @Test("equivalence also applies inside container keys")
    func nestedKeys() {
        // {[1.5 as half]: 0, [1.5 as float]: 1}
        #expect(throws: CBORError.duplicateMapKey(offset: 6)) {
            try CBOR.decode(bytes(fromHex: "a281f93e000081fa3fc0000001"))
        }
    }

    @Test("lenient duplicate handling keeps the last value")
    func lenientDuplicates() throws {
        let options = CBORDecodingOptions(rejectDuplicateMapKeys: false)
        let decoded = try CBOR.decode(bytes(fromHex: "a2f9000000f9800001"), options: options)
        #expect(decoded.mapValue?.count == 1)
        #expect(decoded.mapValue?[.half(bitPattern: 0)] == 1)
        #expect(decoded.mapValue?[.double(-0.0)] == 1)
    }

    @Test("hashes and dictionary lookups follow float equivalence")
    func hashableFloats() {
        let equalGroups: [[CBOR]] = [
            [.half(bitPattern: 0x0000), .half(bitPattern: 0x8000), .float(-0.0), .double(0.0)],
            [.half(bitPattern: 0x3e00), .float(1.5), .double(1.5)],
            [.half(bitPattern: 0x7e00), .half(bitPattern: 0xfe00),
             .float(Float(bitPattern: 0x7fc0_0000)),
             .double(Double(bitPattern: 0x7ff8_0000_0000_0000))],
        ]
        for group in equalGroups {
            for item in group {
                #expect(item == group[0])
                #expect(item.hashValue == group[0].hashValue)
            }
            var dictionary: [CBOR: Int] = [:]
            for (index, item) in group.enumerated() { dictionary[item] = index }
            #expect(dictionary.count == 1)
            for item in group { #expect(dictionary[item] == group.count - 1) }
        }

        #expect(CBOR.half(bitPattern: 0x7e01) != .half(bitPattern: 0x7e00))
        #expect(CBOR.unsignedInt(1) != .half(bitPattern: 0x3c00))

        let halfMap = CBOR.map([.half(bitPattern: 0x3e00): 0])
        let doubleMap = CBOR.map([.double(1.5): 0])
        #expect(halfMap == doubleMap)
        #expect(halfMap.hashValue == doubleMap.hashValue)
    }
}
