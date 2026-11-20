import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // The other targets pin one decoder configuration, so everything they find
    // is a bug reachable with default options. This one fuzzes the options too:
    // the depth limit and duplicate-key rejection are both part of the
    // decoder's behaviour and both have their own edge cases.
    //
    // The provider takes control values from the back of the input and the
    // payload from the front, so mutating the CBOR bytes does not reshuffle the
    // configuration — the fuzzer can hold one fixed while exploring the other.
    FuzzTarget.structured("CBORDecodingOptions") { data in
        let options = CBORDecodingOptions(
            maximumDepth: Int(data.integer(in: UInt16(1)...UInt16(2048))),
            rejectDuplicateMapKeys: data.bool()
        )

        guard let value = try? CBOR.decode(data.remainingBytes(), options: options) else { return }

        // Whatever the options, bytes produced by encoding must decode again.
        let once = value.encode()
        guard let again = try? CBOR.decode(once, options: options) else {
            fatalError("re-encoding a decoded value produced bytes that no longer decode")
        }

        // And encoding is a fixed point, because map keys are always sorted.
        // Without the sort, a map would be written in `Dictionary` order, which
        // differs between two separately decoded values: fuzzing found that
        // within 90 seconds via `a2 01 00 00 00`, a two-entry map.
        guard again.encode() == once else {
            fatalError("encoding is not a fixed point")
        }
    }
}
