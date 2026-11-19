import Testing
import CBOR

@Suite("Floating point")
struct FloatTests {
    @Test("half NaN decodes to a NaN half")
    func decodeHalfNaN() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "f97e00"))
        guard case .half(let bits) = decoded else {
            Issue.record("expected .half, got \(decoded)")
            return
        }
        #expect(bits == 0x7e00)
        #expect(decoded.doubleValue?.isNaN == true)
    }

    @Test("float NaN decodes to a NaN float")
    func decodeFloatNaN() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "fa7fc00000"))
        guard case .float(let value) = decoded else {
            Issue.record("expected .float, got \(decoded)")
            return
        }
        #expect(value.isNaN)
    }

    @Test("double NaN decodes to a NaN double")
    func decodeDoubleNaN() throws {
        let decoded = try CBOR.decode(bytes(fromHex: "fb7ff8000000000000"))
        guard case .double(let value) = decoded else {
            Issue.record("expected .double, got \(decoded)")
            return
        }
        #expect(value.isNaN)
    }

    @Test("canonical NaN encodings")
    func encodeNaN() {
        #expect(hexString(CBOR.half(bitPattern: 0x7e00).encode()) == "f97e00")
        #expect(hexString(CBOR.float(.nan).encode()) == "fa7fc00000")
        #expect(hexString(CBOR.double(.nan).encode()) == "fb7ff8000000000000")
    }

    @Test("negative zero is preserved by bit pattern")
    func negativeZero() throws {
        #expect(hexString(CBOR.half(bitPattern: 0x8000).encode()) == "f98000") // -0.0
        #expect(hexString(CBOR.half(bitPattern: 0x0000).encode()) == "f90000") // +0.0

        let decoded = try CBOR.decode(bytes(fromHex: "f98000"))
        guard case .half(let bits) = decoded else {
            Issue.record("expected .half")
            return
        }
        #expect(bits == 0x8000)
        #expect(decoded.doubleValue?.sign == .minus)
        #expect(decoded.doubleValue == 0.0)
    }

    @Test("float widths are preserved (no cross-width shortening)")
    func widthsPreserved() {
        // A value representable in a narrower type still encodes at its declared width.
        #expect(hexString(CBOR.double(1.0).encode()) == "fb3ff0000000000000")
        #expect(hexString(CBOR.float(1.0).encode()) == "fa3f800000")
        #expect(hexString(CBOR.half(bitPattern: 0x3c00).encode()) == "f93c00") // 1.0
    }

    @Test("infinities round-trip at each width")
    func infinities() throws {
        for hex in ["f97c00", "f9fc00", "fa7f800000", "faff800000", "fb7ff0000000000000", "fbfff0000000000000"] {
            let decoded = try CBOR.decode(bytes(fromHex: hex))
            #expect(hexString(decoded.encode()) == hex)
        }
    }
}
