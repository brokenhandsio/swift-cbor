import Testing
import CBOR

// These mirror how swift-webauthn reads CBOR: COSE_Key maps with integer keys,
// attestation objects with text keys, and length-detection of an embedded item.
@Suite("WebAuthn access patterns")
struct WebAuthnFixtureTests {
    // A COSE EC2 P-256 public key (RFC 9052 §7): kty=2, alg=-7, crv=1, x, y.
    static let x = [UInt8](repeating: 0xa1, count: 32)
    static let y = [UInt8](repeating: 0xb2, count: 32)

    static var coseKey: CBOR {
        [
            .unsignedInt(1): .unsignedInt(2),    // kty: EC2
            .unsignedInt(3): .negativeInt(6),    // alg: ES256 (-7)
            .negativeInt(0): .unsignedInt(1),    // crv: P-256  (key -1)
            .negativeInt(1): .byteString(x),     // x           (key -2)
            .negativeInt(2): .byteString(y),     // y           (key -3)
        ]
    }

    @Test("COSE key round-trips and reads back by integer key")
    func coseKeyAccess() throws {
        let encoded = Self.coseKey.encode()
        let key = try CBOR.decode(encoded)

        #expect(key[.unsignedInt(1)] == .unsignedInt(2))
        #expect(key[.unsignedInt(3)] == .negativeInt(6))
        #expect(key[.unsignedInt(3)]?.int == -7)
        #expect(key[.negativeInt(0)] == .unsignedInt(1))
        #expect(key[.negativeInt(1)]?.bytes == Self.x)
        #expect(key[.negativeInt(2)]?.bytes == Self.y)
    }

    @Test("COSE key encodes in CTAP2 canonical key order")
    func coseKeyCanonicalOrder() {
        // Keys sort bytewise: 0x01, 0x03, 0x20 (-1), 0x21 (-2), 0x22 (-3).
        let encoded = Self.coseKey.encode()
        // Map header 0xa5, then the first two key/value pairs and the third key,
        // in canonical order. `prefix` keeps this slice-safe on empty input.
        #expect(Array(encoded.prefix(6)) == [0xa5, 0x01, 0x02, 0x03, 0x26, 0x20])
    }

    @Test("attestation object with fmt=none")
    func attestationObject() throws {
        let authData = [UInt8](repeating: 0x07, count: 37)
        let attestation: CBOR = [
            "fmt": "none",
            "attStmt": [:],
            "authData": .byteString(authData),
        ]
        let decoded = try CBOR.decode(attestation.encode())

        #expect(decoded["fmt"] == .textString("none"))
        #expect(decoded["attStmt"] == .map([:]))
        #expect(decoded["authData"]?.bytes == authData)

        // The empty-map equality check used by AttestationObject.verify.
        #expect(decoded["attStmt"] == .map([:]))
    }

    @Test("decodeFirst reports the length of an embedded item")
    func embeddedItemLength() throws {
        // AuthenticatorData decodes the COSE key that sits at the tail of authData,
        // then uses how many bytes it consumed to slice the key out.
        let keyBytes = Self.coseKey.encode()
        var buffer = keyBytes
        buffer.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF]) // trailing bytes

        let (value, consumed) = try CBOR.decodeFirst(buffer)
        #expect(consumed == keyBytes.count)
        #expect(value == Self.coseKey)
    }
}
