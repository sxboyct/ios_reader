import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? {
        switch self {
        case .string(let v): v
        case .number(let v): v.rounded() == v ? String(format: "%.0f", v) : String(v)
        default: nil
        }
    }
    public var int: Int? { string.flatMap(Int.init) }
    public var object: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    public var array: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
}

public enum WebAddress {
    /// An address a person typed or pasted: full-width `：／` become ASCII, and a bare host such as
    /// `example.com/config.json` or `192.168.1.5:8080/a` gets `http://` (as browsers do). Text with a
    /// space, another scheme, or no dot in the host is left for `resolve` to reject.
    public static func resolve(typed text: String) throws -> URL {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "／", with: "/")
        if value.range(of: "^[^\\s/?#:]+\\.[^\\s/?#:]+(:[0-9]+)?([/?#]\\S*)?$", options: .regularExpression) != nil {
            value = "http://" + value
        }
        return try resolve(value)
    }
    public static func resolve(_ text: String, relativeTo base: URL? = nil) throws -> URL {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // As browsers do (WHATWG URL), an absolute http(s) address ignores missing or extra slashes:
        // "https:/host/path" is "https://host/path". Only standalone addresses: a base keeps Foundation's rules.
        if base == nil { value = value.replacingOccurrences(of: "^(?i)(https?):/+", with: "$1://", options: .regularExpression) }
        // Encode Unicode without re-encoding existing %HH sequences. Foundation's
        // automatic repair can otherwise turn %26 into %2526 in mixed Unicode URLs.
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.insert(charactersIn: "#")
        guard !value.isEmpty, let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed) else { throw TVError.invalidURL }
        var encoded = escaped.replacingOccurrences(of: "%25([0-9A-Fa-f]{2})", with: "%$1", options: .regularExpression)
        // Brackets are legal in an IPv6 authority, but must be escaped in filenames.
        // Leaving a filename's brackets raw makes Foundation repair the whole URL,
        // encoding existing percent escapes a second time.
        if let authority = encoded.range(of: "^(?:[A-Za-z][A-Za-z0-9+.-]*:)?//[^/?#]*", options: .regularExpression) {
            let host = encoded[authority].replacingOccurrences(of: "%5B", with: "[", options: .caseInsensitive)
                .replacingOccurrences(of: "%5D", with: "]", options: .caseInsensitive)
            encoded.replaceSubrange(authority, with: host)
        }
        guard var components = URLComponents(string: encoded) else { throw TVError.invalidURL }
        // Setting the decoded host asks Foundation to apply IDNA (Punycode).
        if let host = components.host { components.host = host }
        guard let url = components.url(relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { throw TVError.invalidURL }
        return url
    }
}

public enum TVError: LocalizedError, Sendable {
    case invalidURL, invalidConfiguration, http(Int), unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.text("Enter a valid HTTP or HTTPS URL.")
        case .invalidConfiguration: "Invalid book source configuration."
        case .http(let code): L10n.text("The server returned HTTP %lld.", code)
        case .unsupported(let reason): reason
        }
    }
}
