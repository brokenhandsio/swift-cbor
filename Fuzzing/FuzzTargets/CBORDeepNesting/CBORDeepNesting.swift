import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // Nesting is bounded by CBOROptions.maximumSupportedDepth, not by
    // maximumDepth, because CBOR is a recursive value type: parsing walks it on
    // an explicit heap stack, but the Swift runtime *releases* it recursively
    // and that cannot be intercepted. Asking for `.max` therefore gets the
    // ceiling, and this target exercises exactly that boundary — inputs at the
    // ceiling must decode and then tear down safely, and deeper ones must fail
    // as ordinary errors rather than overflowing the stack.
    //
    // Run with a large -max_len: one byte of input is one level of nesting, so
    // the default 4096 barely reaches the ceiling.
    let options = CBOROptions(maximumDepth: .max)

    FuzzTarget("CBORDeepNesting") { bytes in
        _ = try? CBOR.decode(bytes, options: options)
    }
}
