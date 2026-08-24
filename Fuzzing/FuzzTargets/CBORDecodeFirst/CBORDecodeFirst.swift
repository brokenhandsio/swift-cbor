import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // `decodeFirst` reports how many bytes the first item consumed, and callers
    // use that number to slice. swift-webauthn does exactly this: it infers the
    // length of an attested credential's public key by decoding one item, then
    // subtracts that length from a running count and slices with the result.
    // Nothing on either side of that boundary checks the number.
    //
    // The whole of that caller's memory safety therefore rests on one property
    // of this function, which nothing asserted until now: it can never report
    // consuming more than it was given.
    FuzzTarget("CBORDecodeFirst") { bytes in
        guard let (value, consumed) = try? CBOR.decodeFirst(bytes) else { return }

        // The property the callers depend on. A `consumed` larger than the
        // input turns every downstream `bytes[..<consumed]` into a trap, and
        // every `remaining -= consumed` into a negative number that guards
        // written as `!= 0` will happily accept.
        guard consumed <= bytes.count else {
            fatalError("decodeFirst reported \(consumed) bytes consumed from \(bytes.count)")
        }
        guard consumed >= 0 else {
            fatalError("decodeFirst reported a negative byte count: \(consumed)")
        }

        // And the number has to mean what callers take it to mean: the prefix
        // it identifies must be exactly the item that was decoded. A count
        // that is merely in-bounds but wrong still mis-slices the key.
        var prefix = [UInt8]()
        prefix.reserveCapacity(consumed)
        for index in 0..<consumed { prefix.append(bytes[index]) }

        guard let (again, consumedAgain) = try? CBOR.decodeFirst(prefix) else {
            fatalError("the prefix decodeFirst identified does not decode on its own")
        }
        guard consumedAgain == consumed else {
            fatalError("re-decoding the prefix consumed \(consumedAgain), not \(consumed)")
        }
        guard again == value else {
            fatalError("re-decoding the prefix produced a different value")
        }
    }
}
