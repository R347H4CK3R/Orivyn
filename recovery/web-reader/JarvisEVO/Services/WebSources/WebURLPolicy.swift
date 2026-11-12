import Foundation

/// Construct only from an explicit user action. Never feed model output, page links or inferred queries here.
struct UserSuppliedWebURL: Sendable, Equatable {
    let url: URL
    let hostname: String
    let requestTarget: String

    init(_ text: String) throws {
        guard text.utf8.count <= 2_048, text.hasPrefix("https://"),
              text.utf8.allSatisfy({ $0 > 32 && $0 < 127 && $0 != 92 }),
              var parts = URLComponents(string: text), parts.scheme == "https",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased(), !host.isEmpty,
              !host.contains(":"), !host.contains("%"), !host.hasSuffix(".") else { throw WebSourceError.invalidURL }
        let authority = String(text.dropFirst(8).prefix { $0 != "/" })
        guard !authority.contains("%"), !authority.contains("@"),
              authority.lowercased() == host || authority.lowercased() == host + ":443" else { throw WebSourceError.invalidURL }
        if host.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) {
            _ = try PublicWebIPv4(host)
        } else {
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            let reserved = ["localhost", "local", "internal", "home", "lan", "onion", "invalid", "test", "example", "arpa"]
            guard host.utf8.count <= 253, labels.count >= 2,
                  let last = labels.last, !reserved.contains(String(last)),
                  last.utf8.count >= 2, last.utf8.allSatisfy({ (97...122).contains($0) }),
                  labels.allSatisfy({ label in
                      !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                      label.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
                  }) else { throw WebSourceError.invalidURL }
        }
        let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
        guard let decoded = path.removingPercentEncoding,
              !decoded.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !path.contains("\\") else { throw WebSourceError.invalidURL }
        parts.host = host
        parts.percentEncodedPath = path
        guard let url = parts.url else { throw WebSourceError.invalidURL }
        self.url = url
        self.hostname = host
        self.requestTarget = path
    }
}

/// Deliberately IPv4-only. IPv6, mapped/transition addresses and DNS64 are not guessed safe.
struct PublicWebIPv4: Sendable, Equatable {
    let literal: String
    init(_ input: String) throws {
        let components = input.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { throw WebSourceError.unsafeAddress }
        var octets: [UInt8] = []
        for component in components {
            guard !component.isEmpty, component.count <= 3,
                  component.count == 1 || component.first != "0",
                  component.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = UInt8(component) else { throw WebSourceError.unsafeAddress }
            octets.append(number)
        }
        let a = Int(octets[0]), b = Int(octets[1]), c = Int(octets[2])
        guard a != 0, a != 10, a != 127, a < 224,
              !(a == 100 && (64...127).contains(b)), !(a == 169 && b == 254),
              !(a == 172 && (16...31).contains(b)), !(a == 192 && b == 168),
              !(a == 192 && b == 0 && (c == 0 || c == 2)), !(a == 192 && b == 88 && c == 99),
              !(a == 198 && (b == 18 || b == 19)), !(a == 198 && b == 51 && c == 100),
              !(a == 203 && b == 0 && c == 113) else { throw WebSourceError.unsafeAddress }
        literal = input
    }
}
