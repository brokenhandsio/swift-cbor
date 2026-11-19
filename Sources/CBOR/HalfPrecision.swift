/// Conversions from the IEEE 754 half-precision bit patterns that
/// ``CBOR/half(bitPattern:)`` holds.
///
/// `Float16` does this directly, but it is unavailable on Intel Macs (x86_64
/// macOS and Mac Catalyst), which is why the value model stores bits in the first
/// place. Everywhere else `Float16` does the conversion; on Intel Macs it is done
/// by hand. Every half value is exactly representable as a `Float`, so neither
/// path rounds; the one change either makes is that a signalling NaN comes back
/// quiet, as IEEE 754 conversion requires.
@usableFromInline
enum HalfPrecision {
    @inlinable
    static func float(fromBits bits: UInt16) -> Float {
        #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
        return floatByHand(fromBits: bits)
        #else
        return Float(Float16(bitPattern: bits))
        #endif
    }

    @inlinable
    static func double(fromBits bits: UInt16) -> Double {
        #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
        return Double(floatByHand(fromBits: bits))
        #else
        return Double(Float16(bitPattern: bits))
        #endif
    }

    /// `float(fromBits:)` without `Float16`, for Intel Macs.
    ///
    /// Internal rather than private so tests can check it against `Float16` on
    /// platforms where the `#if` above never reaches it.
    @inlinable
    static func floatByHand(fromBits bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = UInt32(bits >> 10) & 0x1f
        let fraction = UInt32(bits & 0x03ff)
        switch exponent {
        case 0:
            // Zero or subnormal: fraction × 2⁻²⁴, which a Float holds exactly.
            let magnitude = Float(fraction) * 0x1p-24
            return sign == 0 ? magnitude : -magnitude
        case 0x1f where fraction == 0:
            return Float(bitPattern: sign | 0x7f80_0000) // infinity
        case 0x1f:
            // NaN. The payload moves to the top of the Float's, with the quiet bit
            // set, matching what `Float16` (and IEEE 754) does to a signalling NaN.
            return Float(bitPattern: sign | 0x7f80_0000 | (fraction | 0x0200) << 13)
        default:
            // Normal: rebias the exponent from 15 to 127.
            return Float(bitPattern: sign | (exponent + 112) << 23 | fraction << 13)
        }
    }
}
