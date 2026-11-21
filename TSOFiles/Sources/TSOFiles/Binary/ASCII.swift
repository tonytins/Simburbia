import Foundation

/// ASCII text decoding that matches .NET's `Encoding.ASCII`.
///
/// Names and labels decode as .NET's `Encoding.ASCII` decodes them, every byte above 0x7F becoming
/// `?`, so names, and lookups by name, come out the same whatever their bytes.
public enum ASCII {
    /// Decodes bytes as ASCII, keeping NUL characters.
    public static func decode(_ bytes: some Sequence<UInt8>) -> String {
        String(decoding: bytes.map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }, as: UTF8.self)
    }
}

extension String {
    /// The string with trailing NUL characters removed, like .NET's `TrimEnd('\0')`.
    func trimmingTrailingNULs() -> String {
        var trimmed = Substring(self)
        while trimmed.last == "\0" {
            trimmed.removeLast()
        }
        return String(trimmed)
    }
}
