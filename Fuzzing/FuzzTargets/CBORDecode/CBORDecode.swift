import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // Decoding arbitrary bytes must never trap. Malformed input is expected —
    // it should come back as a thrown CBORError, not a crash. Anything that
    // gets past `try?` (a trap, a precondition failure, an overflow, unbounded
    // recursion) is a genuine finding.
    FuzzTarget("CBORDecode") { bytes in
        _ = try? CBOR.decode(Array(bytes))
    }
}
