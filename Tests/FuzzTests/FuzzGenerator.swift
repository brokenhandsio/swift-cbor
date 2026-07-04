import CBOR

/// A small, deterministic PRNG (SplitMix64) so fuzz inputs are reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Emits random **valid** CBOR bytes directly — independent of the library's own
/// encoder, and deliberately including non-canonical forms (over-wide argument
/// encodings, indefinite lengths) that the encoder never produces. This exercises
/// far more of the decoder than feeding it only canonical output would.
struct CBORFuzzGenerator {
    private var rng: SplitMix64

    init(seed: UInt64) { rng = SplitMix64(seed: seed) }

    mutating func nextUInt(_ bound: UInt64) -> UInt64 { rng.next() % bound }

    /// A fresh random valid CBOR item, nested up to `maxDepth`.
    mutating func generate(maxDepth: Int) -> [UInt8] {
        var out: [UInt8] = []
        emitItem(into: &out, depth: maxDepth)
        return out
    }

    // MARK: Item emission

    private mutating func emitItem(into out: inout [UInt8], depth: Int) {
        let kinds: UInt64 = depth > 0 ? 12 : 7
        switch nextUInt(kinds) {
        case 0: emitArgument(major: 0, randomMagnitude(), into: &out)
        case 1: emitArgument(major: 1, randomMagnitude(), into: &out)
        case 2: emitByteString(into: &out, indefinite: nextUInt(4) == 0)
        case 3: emitTextString(into: &out, indefinite: nextUInt(4) == 0)
        case 4: emitSimple(into: &out)
        case 5: emitFloat(into: &out)
        case 6: out.append([0xf4, 0xf5, 0xf6, 0xf7][Int(nextUInt(4))]) // false/true/null/undefined
        case 7: // tag (depth > 0 only)
            emitArgument(major: 6, randomMagnitude(), into: &out)
            emitItem(into: &out, depth: depth - 1)
        case 8: emitArray(into: &out, depth: depth, indefinite: false)
        case 9: emitArray(into: &out, depth: depth, indefinite: true)
        case 10: emitMap(into: &out, depth: depth, indefinite: false)
        default: emitMap(into: &out, depth: depth, indefinite: true)
        }
    }

    /// A random unsigned value of varied magnitude (uniform over bit widths).
    private mutating func randomMagnitude() -> UInt64 {
        rng.next() >> nextUInt(64)
    }

    /// Emit a major-type head + argument, choosing a random valid (possibly
    /// non-minimal) encoding width.
    private mutating func emitArgument(major: UInt8, _ value: UInt64, into out: inout [UInt8]) {
        let head = major << 5
        let widths: [UInt8]
        switch value {
        case 0..<24: widths = [0, 24, 25, 26, 27]
        case 24...0xFF: widths = [24, 25, 26, 27]
        case 0x100...0xFFFF: widths = [25, 26, 27]
        case 0x1_0000...0xFFFF_FFFF: widths = [26, 27]
        default: widths = [27]
        }
        switch widths[Int(nextUInt(UInt64(widths.count)))] {
        case 0: out.append(head | UInt8(value))
        case 24: out.append(head | 24); appendBigEndian(value, width: 1, into: &out)
        case 25: out.append(head | 25); appendBigEndian(value, width: 2, into: &out)
        case 26: out.append(head | 26); appendBigEndian(value, width: 4, into: &out)
        default: out.append(head | 27); appendBigEndian(value, width: 8, into: &out)
        }
    }

    private func appendBigEndian(_ value: UInt64, width: Int, into out: inout [UInt8]) {
        var shift = (width - 1) * 8
        while shift >= 0 {
            out.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            shift -= 8
        }
    }

    private mutating func emitByteString(into out: inout [UInt8], indefinite: Bool) {
        if indefinite {
            out.append(0x5f)
            for _ in 0..<Int(nextUInt(4)) { emitDefiniteByteChunk(into: &out) }
            out.append(0xff)
        } else {
            emitDefiniteByteChunk(into: &out)
        }
    }

    private mutating func emitDefiniteByteChunk(into out: inout [UInt8]) {
        let count = Int(nextUInt(8))
        emitArgument(major: 2, UInt64(count), into: &out)
        for _ in 0..<count { out.append(UInt8(truncatingIfNeeded: rng.next())) }
    }

    private mutating func emitTextString(into out: inout [UInt8], indefinite: Bool) {
        if indefinite {
            out.append(0x7f)
            for _ in 0..<Int(nextUInt(4)) { emitDefiniteTextChunk(into: &out) }
            out.append(0xff)
        } else {
            emitDefiniteTextChunk(into: &out)
        }
    }

    private mutating func emitDefiniteTextChunk(into out: inout [UInt8]) {
        var utf8: [UInt8] = []
        for _ in 0..<Int(nextUInt(6)) { utf8.append(contentsOf: Array(String(randomScalar()).utf8)) }
        emitArgument(major: 3, UInt64(utf8.count), into: &out)
        out.append(contentsOf: utf8)
    }

    private mutating func randomScalar() -> Unicode.Scalar {
        while true {
            if let scalar = Unicode.Scalar(UInt32(nextUInt(0x11_0000))) { return scalar }
        }
    }

    private mutating func emitSimple(into out: inout [UInt8]) {
        if nextUInt(2) == 0 {
            out.append(0xe0 | UInt8(nextUInt(20)))              // simple 0...19
        } else {
            out.append(0xf8)
            out.append(UInt8(32 + nextUInt(224)))              // simple 32...255
        }
    }

    private mutating func emitFloat(into out: inout [UInt8]) {
        // Avoid NaN so round-trip equality holds (NaN != NaN); infinities are fine.
        var value = Double(bitPattern: rng.next())
        if value.isNaN { value = Double(nextUInt(1000)) }
        switch nextUInt(3) {
        case 0: out.append(0xf9); appendBigEndian(UInt64(Float16(value).bitPattern), width: 2, into: &out)
        case 1: out.append(0xfa); appendBigEndian(UInt64(Float(value).bitPattern), width: 4, into: &out)
        default: out.append(0xfb); appendBigEndian(value.bitPattern, width: 8, into: &out)
        }
    }

    private mutating func emitArray(into out: inout [UInt8], depth: Int, indefinite: Bool) {
        let count = Int(nextUInt(5))
        if indefinite {
            out.append(0x9f)
            for _ in 0..<count { emitItem(into: &out, depth: depth - 1) }
            out.append(0xff)
        } else {
            emitArgument(major: 4, UInt64(count), into: &out)
            for _ in 0..<count { emitItem(into: &out, depth: depth - 1) }
        }
    }

    private mutating func emitMap(into out: inout [UInt8], depth: Int, indefinite: Bool) {
        let count = Int(nextUInt(5))
        if indefinite {
            out.append(0xbf)
            for _ in 0..<count {
                emitItem(into: &out, depth: depth - 1) // key
                emitItem(into: &out, depth: depth - 1) // value
            }
            out.append(0xff)
        } else {
            emitArgument(major: 5, UInt64(count), into: &out)
            for _ in 0..<count {
                emitItem(into: &out, depth: depth - 1)
                emitItem(into: &out, depth: depth - 1)
            }
        }
    }

    // MARK: Mutation

    /// Corrupt `bytes` in place with a few random edits (bit flips, byte sets,
    /// truncation, insertion, deletion) to produce "almost-valid" inputs.
    mutating func mutate(_ bytes: inout [UInt8]) {
        for _ in 0..<(1 + Int(nextUInt(3))) {
            guard !bytes.isEmpty else {
                bytes.append(UInt8(truncatingIfNeeded: rng.next()))
                continue
            }
            let index = Int(nextUInt(UInt64(bytes.count)))
            switch nextUInt(5) {
            case 0: bytes[index] ^= UInt8(1) << UInt8(nextUInt(8))
            case 1: bytes[index] = UInt8(truncatingIfNeeded: rng.next())
            case 2: bytes.removeLast(bytes.count - index)
            case 3: bytes.insert(UInt8(truncatingIfNeeded: rng.next()), at: index)
            default: bytes.remove(at: index)
            }
        }
    }
}
