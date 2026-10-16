//
//  ProtocolFetching.swift
//  ProtocolParser
//
//  The IO seam (`docs/architecture/protocol-parser.md` §7.3): the only place the module touches the
//  network, faked in tests so the parser itself is pure.
//

import Foundation

/// Fetches one page as text. Tests supply fixture text through a fake instead.
///
/// The requirement is `nonisolated`: every target is MainActor-isolated by default
/// (`Project.swift` `baseSettings`), so without it the protocol would be MainActor-only and no
/// actor (or off-main fetcher) could conform to it.
public nonisolated protocol ProtocolFetching: Sendable {
    func fetch(_ url: URL) async throws -> String
}

/// The production fetcher: a plain GET with caching disabled (the pages send `no-cache`).
public struct URLSessionProtocolFetcher: ProtocolFetching {
    public init() {}

    public nonisolated func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProtocolParserError.fetchFailed(statusCode: http.statusCode)
        }
        guard let text = Self.decode(data) else { throw ProtocolParserError.undecodableBody }
        return text
    }

    /// UTF-8 first, then ISO-8859-1 — the pages declare `charset=iso-8859-1` (protocol-parser.md §4.2).
    nonisolated static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
