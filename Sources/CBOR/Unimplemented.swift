/// A placeholder error thrown by not-yet-implemented entry points.
///
/// This exists so that, before the encode/decode implementations land, the test
/// suite can run and report failures rather than trapping the whole process. It is
/// internal and will be removed once every entry point is implemented.
struct CBORUnimplementedError: Error, CustomStringConvertible {
    let symbol: String
    var description: String { "\(symbol) is not implemented yet" }
}
