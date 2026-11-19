import Testing
import CBOR

@Suite("Deterministic encoding (RFC 8949 §4.2)")
struct DeterministicEncodingTests {
    @Test("integers use the shortest form")
    func shortestInteger() {
        #expect(hexString(CBOR.unsignedInt(0).encode()) == "00")
        #expect(hexString(CBOR.unsignedInt(23).encode()) == "17")
        #expect(hexString(CBOR.unsignedInt(24).encode()) == "1818")
        #expect(hexString(CBOR.unsignedInt(255).encode()) == "18ff")
        #expect(hexString(CBOR.unsignedInt(256).encode()) == "190100")
        #expect(hexString(CBOR.unsignedInt(65535).encode()) == "19ffff")
        #expect(hexString(CBOR.unsignedInt(65536).encode()) == "1a00010000")
    }

    @Test("map keys are sorted into bytewise lexicographic order")
    func sortedKeys() {
        // Inserted out of order; must encode 1 before 3.
        let map: CBOR = [3: 4, 1: 2]
        #expect(hexString(map.encode()) == "a201020304")
    }

    @Test("shorter key encodings sort before longer ones")
    func lengthOrdering() {
        // key 10 -> 0x0a (1 byte), key 100 -> 0x1864 (2 bytes): 0x0a sorts first.
        let map: CBOR = [100: 2, 10: 1]
        #expect(hexString(map.encode()) == "a20a01186402")
    }

    @Test("integer keys sort before text keys")
    func mixedKeyTypes() {
        // key 1 -> 0x01, key "a" -> 0x6161: integer first.
        // a2 01 08 6161 09
        let map: CBOR = [.textString("a"): 9, .unsignedInt(1): 8]
        #expect(hexString(map.encode()) == "a20108616109")
    }

    @Test("floats keep the width of their case rather than being narrowed")
    func floatsKeepTheirWidth() {
        // RFC 8949 §4.2.1 would write all three as the half f93e00. swift-cbor
        // keeps the declared width, as CTAP2's canonical form also requires.
        #expect(hexString(CBOR.half(bitPattern: 0x3e00).encode()) == "f93e00")
        #expect(hexString(CBOR.float(1.5).encode()) == "fa3fc00000")
        #expect(hexString(CBOR.double(1.5).encode()) == "fb3ff8000000000000")
    }

    @Test("lengths are always definite")
    func definiteLengths() throws {
        // An indefinite-length array and map decode, but encode with definite lengths.
        let array = try CBOR.decode([0x9f, 0x01, 0x02, 0xff])
        #expect(hexString(array.encode()) == "820102")
        let map = try CBOR.decode([0xbf, 0x61, 0x61, 0x01, 0xff])
        #expect(hexString(map.encode()) == "a1616101")
    }

    @Test("the Codable encoder sorts keys too")
    func codableKeysSorted() throws {
        // Declared out of order; "a" (6161) sorts before "b" (6162).
        struct OutOfOrder: Encodable { var b = 2; var a = 1 }
        #expect(hexString(try CBOREncoder().encode(OutOfOrder())) == "a2616101616202")
    }

    @Test("encoding is stable across repeated calls")
    func stability() {
        let map: CBOR = ["a": "A", "b": "B", "c": "C", "d": "D", "e": "E"]
        let first = map.encode()
        let second = map.encode()
        #expect(first == second)
        #expect(hexString(first) == "a56161614161626142616361436164614461656145")
    }
}
