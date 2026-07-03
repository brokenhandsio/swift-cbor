import Testing
import CBOR

@Suite("Indefinite-length decoding")
struct IndefiniteLengthTests {
    @Test("indefinite byte string chunks concatenate")
    func byteString() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "5f42010243030405ff"))
        #expect(decoded == .byteString([0x01, 0x02, 0x03, 0x04, 0x05]))
    }

    @Test("indefinite text string chunks concatenate")
    func textString() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "7f657374726561646d696e67ff"))
        #expect(decoded == .textString("streaming"))
    }

    @Test("empty indefinite byte string")
    func emptyByteString() throws {
        #expect(try CBOR.decode(bytes(fromHex: "5fff")) == .byteString([]))
    }

    @Test("empty indefinite text string")
    func emptyTextString() throws {
        #expect(try CBOR.decode(bytes(fromHex: "7fff")) == .textString(""))
    }

    @Test("indefinite array")
    func array() throws {
        #expect(try CBOR.decode(bytes(fromHex: "9fff")) == .array([]))
        #expect(try CBOR.decode(bytes(fromHex: "9f018202039f0405ffff")) == [1, [2, 3], [4, 5]])
    }

    @Test("indefinite map")
    func map() throws {
        #expect(try CBOR.decode(bytes(fromHex: "bf61610161629f0203ffff")) == ["a": 1, "b": [2, 3]])
        #expect(try CBOR.decode(bytes(fromHex: "bf6346756ef563416d7421ff")) == ["Fun": true, "Amt": -2])
    }

    @Test("indefinite items re-encode in definite form")
    func reencodesDefinite() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "9f01820203820405ff"))
        #expect(hexString(decoded.encode()) == "8301820203820405")
    }
}
