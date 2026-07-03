import CBOR

// MARK: - Hex helpers

/// Parse a hex string (no separators, even length) into bytes.
func bytes(fromHex hex: String) -> [UInt8] {
    precondition(hex.count % 2 == 0, "hex string must have even length")
    var result: [UInt8] = []
    result.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            preconditionFailure("invalid hex: \(hex[index..<next])")
        }
        result.append(byte)
        index = next
    }
    return result
}

/// Render bytes as a lowercase hex string.
func hexString(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef")
    var out = ""
    out.reserveCapacity(bytes.count * 2)
    for byte in bytes {
        out.append(digits[Int(byte >> 4)])
        out.append(digits[Int(byte & 0x0f)])
    }
    return out
}

// MARK: - RFC 8949 test vector

/// One entry from RFC 8949 Appendix A ("Examples of Encoded CBOR Data Items").
struct RFCVector: Sendable, CustomStringConvertible {
    /// The canonical CBOR encoding, as hex.
    let hex: String
    /// The value the encoding decodes to.
    let value: CBOR
    /// Whether re-encoding `value` reproduces `hex`. False for indefinite-length
    /// encodings (which we always decode but re-emit in definite form) and for any
    /// non-canonical example.
    let encodes: Bool

    init(_ hex: String, _ value: CBOR, encodes: Bool = true) {
        self.hex = hex
        self.value = value
        self.encodes = encodes
    }

    var description: String { hex }
}
