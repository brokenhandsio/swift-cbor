/// Options controlling CBOR decoding and encoding.
public struct CBOROptions: Sendable {
    /// The maximum nesting depth to decode, inclusive.
    ///
    /// A top-level primitive has depth 0; each nested array, map or tag increases
    /// the depth by one. Decoding throws ``CBORError/maxDepthExceeded(_:)`` when the
    /// limit would be exceeded. This bounds stack usage on adversarial input.
    /// Defaults to `512`.
    ///
    /// Values above ``maximumSupportedDepth`` have no additional effect: decoding
    /// stops at that ceiling regardless. See its documentation for why.
    public var maximumDepth: Int

    /// When decoding, throw ``CBORError/duplicateMapKey`` if a map contains the same
    /// key more than once. Defaults to `false`.
    public var rejectDuplicateMapKeys: Bool

    /// When encoding, produce RFC 8949 §4.2 "core deterministic" output: integers
    /// and floats use their shortest form and map keys are sorted into bytewise
    /// lexicographic order of their encodings. Defaults to `true`.
    ///
    /// Because ``CBOR/map(_:)`` is backed by an unordered dictionary, deterministic
    /// ordering is the only stable ordering available; disabling this only relaxes
    /// the shortest-form guarantees, not key ordering.
    public var deterministic: Bool

    public init(
        maximumDepth: Int = 512,
        rejectDuplicateMapKeys: Bool = false,
        deterministic: Bool = true
    ) {
        self.maximumDepth = maximumDepth
        self.rejectDuplicateMapKeys = rejectDuplicateMapKeys
        self.deterministic = deterministic
    }

    /// The deepest nesting this library will decode, whatever ``maximumDepth`` says.
    ///
    /// ``CBOR`` is a recursive value type: an array holds `[CBOR]`, whose elements
    /// hold more. Parsing and encoding walk that structure with explicit heap
    /// stacks, and equality and hashing are bounded — but *releasing* a value is
    /// done by the Swift runtime, which recurses once per level and cannot be
    /// intercepted. A value nested deeply enough therefore decodes successfully
    /// and then overflows the stack when it goes out of scope.
    ///
    /// Measured cost is roughly 280 bytes of stack per level, so the ceiling is
    /// really a function of the caller's stack: about 30,000 levels on an 8 MB
    /// main thread but only about 1,800 on a 512 KB thread — which is what Swift
    /// concurrency's cooperative pool gives you. Since a library cannot know
    /// which it is on, it refuses to build values it may be unable to destroy.
    ///
    /// 1024 leaves the default of 512 usable while staying inside the smaller
    /// budget. Deeper input fails with ``CBORError/maxDepthExceeded(_:)``, which
    /// is a normal error rather than a crash.
    public static let maximumSupportedDepth = 1024

    /// The default options.
    public static let `default` = CBOROptions()
}
