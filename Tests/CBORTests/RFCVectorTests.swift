import Testing
import CBOR

@Suite("RFC 8949 Appendix A vectors")
struct RFCVectorTests {
    @Test("decode(hex) == value", arguments: RFCVectors.all)
    func decodes(_ vector: RFCVector) throws {
        let decoded = try CBOR.decode(bytes(fromHex: vector.hex))
        #expect(decoded == vector.value, "decoding \(vector.hex)")
    }

    @Test("encode(value) == hex (canonical vectors)", arguments: RFCVectors.all.filter(\.encodes))
    func encodes(_ vector: RFCVector) {
        let encoded = vector.value.encode()
        #expect(hexString(encoded) == vector.hex)
    }

    @Test("decode then encode is stable for canonical vectors", arguments: RFCVectors.all.filter(\.encodes))
    func roundTripsThroughBytes(_ vector: RFCVector) throws {
        let decoded = try CBOR.decode(bytes(fromHex: vector.hex))
        #expect(hexString(decoded.encode()) == vector.hex)
    }
}
