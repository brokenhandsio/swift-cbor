import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // The other targets pin one decoder configuration, so everything they find
    // is a bug reachable with default options. This one fuzzes the options too:
    // the depth limit, duplicate-key rejection and deterministic encoding are
    // all part of the decoder's behaviour and all have their own edge cases.
    //
    // The provider takes control values from the back of the input and the
    // payload from the front, so mutating the CBOR bytes does not reshuffle the
    // configuration — the fuzzer can hold one fixed while exploring the other.
    FuzzTarget.structured("CBOROptions") { data in
        let deterministic = data.bool()
        let options = CBOROptions(
            maximumDepth: Int(data.integer(in: UInt16(1)...UInt16(2048))),
            rejectDuplicateMapKeys: data.bool(),
            deterministic: deterministic
        )

        guard let value = try? CBOR.decode(data.remainingBytes(), options: options) else { return }

        // Whatever the options, bytes produced by encoding must decode again.
        let once = value.encode(options: options)
        guard let again = try? CBOR.decode(once, options: options) else {
            fatalError("re-encoding a decoded value produced bytes that no longer decode")
        }

        // The stronger fixed-point property holds only under deterministic
        // encoding. With it off, map keys are emitted in `Dictionary` order,
        // which differs between two separately-decoded values — so a map with
        // more than one entry can legitimately encode two ways. Fuzzing found
        // that within 90 seconds via `a2 01 00 00 00`, a two-entry map.
        if deterministic {
            guard again.encode(options: options) == once else {
                fatalError("deterministic encoding is not a fixed point")
            }
        }
    }
}
