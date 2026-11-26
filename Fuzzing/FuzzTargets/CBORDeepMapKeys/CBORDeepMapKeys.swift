import CBOR
import Fuzzing

let fuzzTargets: @Sendable () -> Void = {
    // Random CBOR bytes almost never form a map with many keys that share a
    // deeply nested prefix. Build that shape from the fuzzer's bytes instead.
    // Differences below level 16 used to be ignored by hashing, making map
    // insertion and lookup quadratic in the number of keys.
    FuzzTarget("CBORDeepMapKeys") { bytes in
        guard !bytes.isEmpty else { return }
        let depth = 17 + Int(bytes[0] & 31)
        let count = min(bytes.count, 128)
        var entries: [CBOR: CBOR] = [:]

        for index in 0..<count {
            var key = CBOR.array([
                .unsignedInt(UInt64(index)),
                .unsignedInt(UInt64(bytes[index])),
            ])
            for _ in 0..<depth { key = .array([key]) }
            entries[key] = .unsignedInt(UInt64(index))
        }

        let encoded = CBOR.map(entries).encode()
        guard let decoded = try? CBOR.decode(encoded), case .map(let map) = decoded,
              map.count == entries.count else {
            fatalError("a map with deep keys failed to round-trip")
        }
        for (key, value) in entries {
            guard map[key] == value else {
                fatalError("a deep map key was lost or changed")
            }
        }
    }
}
