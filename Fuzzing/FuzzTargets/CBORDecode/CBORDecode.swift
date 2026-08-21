import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // Decoding arbitrary bytes must never trap. Malformed input is expected —
    // it should come back as a thrown CBORError, not a crash. Anything that
    // gets past `try?` (a trap, a precondition failure, an overflow, unbounded
    // recursion) is a genuine finding.
    //
    // `CBOR.decode` takes a `Span<UInt8>`, which is exactly what the fuzz body
    // receives, so the input goes straight through with nothing copied.
    FuzzTarget("CBORDecode") { bytes in
        _ = try? CBOR.decode(bytes)
    }
}
