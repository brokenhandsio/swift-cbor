import Testing
@testable import CBOR

/// `.half` holds a bit pattern, and `HalfPrecision` turns it into a number: via
/// `Float16` where that exists, by hand on Intel Macs. These pin the by-hand path
/// on every platform, since most test hosts never reach it through the `#if`.
@Suite("Half precision")
struct HalfPrecisionTests {
    @Test("by-hand conversion gives known values", arguments: [
        (UInt16(0x0000), Float(0.0)),
        (0x8000, -0.0),
        (0x3c00, 1.0),
        (0x3e00, 1.5),
        (0xc400, -4.0),
        (0x7bff, 65504.0),                  // largest finite half
        (0x0400, 0.00006103515625),         // smallest normal
        (0x0001, 5.960464477539063e-8),     // smallest subnormal
        (0x03ff, 0.00006097555160522461),   // largest subnormal
        (0x7c00, .infinity),
        (0xfc00, -.infinity),
    ])
    func knownValues(_ bits: UInt16, _ expected: Float) {
        let converted = HalfPrecision.floatByHand(fromBits: bits)
        #expect(converted.bitPattern == expected.bitPattern) // tells -0.0 from +0.0
    }

    @Test("by-hand conversion keeps NaN payloads and quiets signalling NaNs")
    func nans() {
        // Quiet NaN, signalling NaN, and a negative NaN with a payload.
        for bits: UInt16 in [0x7e00, 0x7c01, 0xfe2a] {
            let converted = HalfPrecision.floatByHand(fromBits: bits)
            #expect(converted.isNaN)
            #expect(!converted.isSignalingNaN)
            #expect(converted.sign == (bits & 0x8000 == 0 ? .plus : .minus))
            #expect(converted.bitPattern & 0x007f_ffff == UInt32(bits & 0x03ff | 0x0200) << 13)
        }
    }

    #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
    @Test("by-hand conversion matches Float16 for every bit pattern")
    func matchesFloat16Exhaustively() {
        var mismatches = 0
        for bits in UInt16.min...UInt16.max {
            let byHand = HalfPrecision.floatByHand(fromBits: bits)
            let reference = Float(Float16(bitPattern: bits))
            if byHand.bitPattern != reference.bitPattern {
                mismatches += 1
                Issue.record("0x\(String(bits, radix: 16)): \(byHand) vs Float16's \(reference)")
                if mismatches > 10 { return }
            }
        }
    }
    #endif
}
