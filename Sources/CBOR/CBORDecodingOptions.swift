/// Options controlling how CBOR is decoded, by ``CBOR/decode(_:options:)-(Span<UInt8>,_)``,
/// ``CBOR/decodeFirst(_:options:)-(Span<UInt8>,_)`` and ``CBORDecoder``.
///
/// Encoding takes no options: its output is always deterministic. See
/// ``CBOR/encode()``.
public struct CBORDecodingOptions: Sendable {
    /// The maximum nesting depth to decode, inclusive.
    ///
    /// A top-level primitive has depth 0; each nested array, map or tag increases
    /// the depth by one. Decoding throws ``CBORError/maxDepthExceeded(limit:offset:)`` when the
    /// limit would be exceeded. This bounds stack usage on adversarial input.
    /// Defaults to `512`.
    ///
    /// Values above ``maximumSupportedDepth`` have no additional effect: decoding
    /// stops at that ceiling regardless. See its documentation for why.
    public var maximumDepth: Int

    /// Throw ``CBORError/duplicateMapKey(offset:)`` if a map contains the same
    /// key more than once. Defaults to `true`.
    ///
    /// RFC 8949 §5.6 says a map with a duplicate key is not valid CBOR, and
    /// decoders disagree about which value such a map means. Rejecting it means
    /// bytes that another decoder reads differently never decode silently. Keys
    /// are compared as decoded values, so `1` written in one byte and `1` written in
    /// two are the same key. Floats compare by bit pattern, so `0.0` and `-0.0` are
    /// different keys, as are `1` and `1.0`.
    ///
    /// Set this to `false` to accept such maps; the last value for a key then wins.
    public var rejectDuplicateMapKeys: Bool

    public init(
        maximumDepth: Int = 512,
        rejectDuplicateMapKeys: Bool = true
    ) {
        self.maximumDepth = maximumDepth
        self.rejectDuplicateMapKeys = rejectDuplicateMapKeys
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
    /// budget. Deeper input fails with ``CBORError/maxDepthExceeded(limit:offset:)``, which
    /// is a normal error rather than a crash.
    public static let maximumSupportedDepth = 1024

    /// The default options.
    public static let `default` = CBORDecodingOptions()
}
