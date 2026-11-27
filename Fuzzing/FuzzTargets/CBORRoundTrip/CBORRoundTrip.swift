import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // Encoding is a fixed point: once a value has been through one
    // encode/decode cycle, further cycles must not change its bytes.
    //
    // The original bytes need not be reproduced because non-shortest integers
    // and unsorted maps are legal inputs. The decoded value, however, must stay
    // equivalent under RFC 8949 map-key rules after re-encoding.
    //
    // NaN significands are part of that equality, so NaNs round-trip as well.
    FuzzTarget("CBORRoundTrip") { bytes in
        guard let first = try? CBOR.decode(bytes) else { return }
        let once = first.encode()

        guard let second = try? CBOR.decode(once) else {
            fatalError("re-encoding a decoded value produced bytes that no longer decode")
        }
        guard first == second else {
            fatalError("encoding changed the decoded CBOR value")
        }
        let twice = second.encode()

        guard once == twice else {
            fatalError("encoding is not a fixed point: a second cycle changed the bytes")
        }
    }
}
