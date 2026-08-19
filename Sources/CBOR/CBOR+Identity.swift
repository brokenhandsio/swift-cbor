// MARK: - Value identity
//
// `==` is written out rather than synthesized so that the three float cases
// compare by bit pattern instead of by IEEE equality. `hash(into:)` is written
// out so that hashing a deeply nested value cannot overflow the stack.
//
// Synthesis would give `.double(.nan) != .double(.nan)`, which is right for
// arithmetic and wrong for a data model. Two CBOR items are the same item when
// they encode to the same bytes, and a NaN payload encodes to exactly itself.
// Under IEEE semantics a `[CBOR: CBOR]` would accept the same NaN key twice —
// the map then holds two entries whose encoded keys are byte-identical, so the
// deterministic key sort (RFC 8949 §4.2.1, bytewise over encoded keys) has no
// total order to work with. The same map could encode two different ways, and
// the output contained a duplicate key, which is not valid deterministic CBOR
// at all. Found by fuzzing; see FloatKeyIdentityTests.
//
// Two consequences worth knowing:
//
// - Distinct NaN payloads stay distinct, because their bit patterns and
//   therefore their encodings differ.
// - `0.0` and `-0.0` are now different keys. They encode differently
//   (`0xfb 0000…` vs `0xfb 8000…`), so collapsing them would reintroduce the
//   same ambiguity from the other direction.

extension CBOR {
    public static func == (lhs: CBOR, rhs: CBOR) -> Bool {
        // Fast path. Scalars are the overwhelming majority of comparisons —
        // every map-key lookup during decoding lands here — so they must not
        // touch the heap. Only the three container cases fall through to the
        // iterative walk below.
        switch (lhs, rhs) {
        case (.unsignedInt(let a), .unsignedInt(let b)): return a == b
        case (.negativeInt(let a), .negativeInt(let b)): return a == b
        case (.byteString(let a), .byteString(let b)): return a == b
        case (.textString(let a), .textString(let b)): return a == b
        case (.simple(let a), .simple(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.undefined, .undefined): return true
        // Bit patterns rather than IEEE equality: see the note above.
        case (.half(let a), .half(let b)): return a.bitPattern == b.bitPattern
        case (.float(let a), .float(let b)): return a.bitPattern == b.bitPattern
        case (.double(let a), .double(let b)): return a.bitPattern == b.bitPattern
        case (.array, .array), (.map, .map), (.tagged, .tagged):
            return deepEqual(lhs, rhs)
        default:
            return false
        }
    }

    /// Structural comparison of two containers, walked with an explicit stack.
    ///
    /// Native recursion here would be a stack overflow waiting to happen: a
    /// value nested `n` deep costs `n` frames, and `n` is attacker-controlled
    /// up to `CBOROptions.maximumDepth`, which callers may raise. The parser
    /// and encoder avoid recursion for the same reason, so comparison should
    /// not be the one place that reintroduces the limit.
    private static func deepEqual(_ lhs: CBOR, _ rhs: CBOR) -> Bool {
        var pending: [(CBOR, CBOR)] = [(lhs, rhs)]

        while let (left, right) = pending.popLast() {
            switch (left, right) {
            case (.array(let a), .array(let b)):
                guard a.count == b.count else { return false }
                for index in a.indices {
                    pending.append((a[index], b[index]))
                }
            case (.map(let a), .map(let b)):
                guard a.count == b.count else { return false }
                for (key, value) in a {
                    // Looking the key up in `b` hashes it, which is where key
                    // identity — and therefore the float bit-pattern rule —
                    // actually gets applied.
                    guard let other = b[key] else { return false }
                    pending.append((value, other))
                }
            case (.tagged(let tagA, let a), (.tagged(let tagB, let b))):
                guard tagA == tagB else { return false }
                pending.append((a, b))
            default:
                // Scalars and mismatched cases: the fast path above is
                // non-recursive, so this cannot re-enter `deepEqual`.
                guard left == right else { return false }
            }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hash(into: &hasher, depthBudget: Self.hashDepthBudget)
    }

    /// How far into a value hashing descends.
    ///
    /// Synthesized hashing recursed once per level of nesting and overflowed the
    /// stack somewhere between depth 512 and 1000 — uncomfortably close to the
    /// default `CBOROptions.maximumDepth` of 512, and reachable from decoded
    /// input the moment a caller raises that limit, because the parser stores
    /// map keys with `pairs[key] = value`.
    ///
    /// Bounding the descent fixes that without an explicit work stack. Hashing
    /// may legitimately look at part of a value rather than all of it: the
    /// contract is that equal values hash equally, and a bounded projection of
    /// two equal values is still equal. Values differing only below this depth
    /// collide, and `==` — which is exact, and iterative — separates them.
    ///
    /// 16 is far past anything real CBOR nests keys to, and costs at most 16
    /// frames.
    private static let hashDepthBudget = 16

    private func hash(into hasher: inout Hasher, depthBudget: Int) {
        switch self {
        case .unsignedInt(let value):
            hasher.combine(0 as UInt8)
            hasher.combine(value)
        case .negativeInt(let value):
            hasher.combine(1 as UInt8)
            hasher.combine(value)
        case .byteString(let value):
            hasher.combine(2 as UInt8)
            hasher.combine(value)
        case .textString(let value):
            hasher.combine(3 as UInt8)
            hasher.combine(value)
        case .simple(let value):
            hasher.combine(7 as UInt8)
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(8 as UInt8)
            hasher.combine(value)
        case .null:
            hasher.combine(9 as UInt8)
        case .undefined:
            hasher.combine(10 as UInt8)
        // Bit patterns, to stay consistent with `==`. The standard library
        // would do the same except for normalising -0.0 to +0.0, which `==` now
        // treats as a different value.
        case .half(let value):
            hasher.combine(11 as UInt8)
            hasher.combine(value.bitPattern)
        case .float(let value):
            hasher.combine(12 as UInt8)
            hasher.combine(value.bitPattern)
        case .double(let value):
            hasher.combine(13 as UInt8)
            hasher.combine(value.bitPattern)

        case .array(let elements):
            hasher.combine(4 as UInt8)
            hasher.combine(elements.count)
            guard depthBudget > 0 else { return }
            for element in elements {
                element.hash(into: &hasher, depthBudget: depthBudget - 1)
            }
        case .map(let entries):
            hasher.combine(5 as UInt8)
            hasher.combine(entries.count)
            guard depthBudget > 0 else { return }
            // Combined commutatively, because a dictionary has no order: two
            // equal maps must hash the same however they happen to iterate.
            // This is what `Dictionary.hash(into:)` does, done here so the
            // depth budget reaches the elements.
            var commutative = 0
            for (key, value) in entries {
                var element = Hasher()
                key.hash(into: &element, depthBudget: depthBudget - 1)
                value.hash(into: &element, depthBudget: depthBudget - 1)
                commutative ^= element.finalize()
            }
            hasher.combine(commutative)
        case .tagged(let tag, let value):
            hasher.combine(6 as UInt8)
            hasher.combine(tag)
            guard depthBudget > 0 else { return }
            value.hash(into: &hasher, depthBudget: depthBudget - 1)
        }
    }
}
