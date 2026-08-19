import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // Encoding is a fixed point: once a value has been through one
    // encode/decode cycle, further cycles must not change its bytes.
    //
    // Two weaker-looking properties are deliberately NOT asserted, because both
    // have legitimate counterexamples:
    //
    //   encode(decode(x)) == x   Non-canonical encodings are legal CBOR (an
    //                            integer stored wider than it needs to be,
    //                            unsorted map keys); re-encoding normalises them.
    //
    //   decode(x) == decode(encode(decode(x)))
    //                            Fails on NaN payloads, since NaN != NaN. Fuzzing
    //                            found this within seconds via the input
    //                            `fa ffff9f01`, a single-precision NaN.
    //
    // Comparing the *encodings* of two successive cycles sidesteps both: the
    // first cycle normalises, and NaN encodes to stable bytes even though it
    // never compares equal to itself.
    FuzzTarget("CBORRoundTrip") { bytes in
        guard let first = try? CBOR.decode(Array(bytes)) else { return }
        let once = first.encode()

        guard let second = try? CBOR.decode(once) else {
            fatalError("re-encoding a decoded value produced bytes that no longer decode")
        }
        let twice = second.encode()

        guard once == twice else {
            fatalError("encoding is not a fixed point: a second cycle changed the bytes")
        }
    }
}
