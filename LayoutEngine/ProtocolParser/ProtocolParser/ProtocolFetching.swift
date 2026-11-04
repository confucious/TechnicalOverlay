//
//  ProtocolFetching.swift
//  ProtocolParser
//
//  The IO seam (`docs/architecture/protocol-parser.md` §7.3): the only place the module touches the
//  network, faked in tests so the parsers themselves are pure.
//

import Foundation

/// Fetches one document's bytes. Tests supply fixture content through a fake instead.
///
/// The seam is bytes, not text: a protocol is either an HTML page or a PDF, and only the importer,
/// after sniffing the body, knows which. Decoding here would decide that too early.
///
/// The requirement is `nonisolated`: every target is MainActor-isolated by default
/// (`Project.swift` `baseSettings`), so without it the protocol would be MainActor-only and no
/// actor (or off-main fetcher) could conform to it.
public nonisolated protocol ProtocolFetching: Sendable {
    func fetchData(_ url: URL) async throws -> Data
}

extension ProtocolFetching {
    /// The body as text — UTF-8 first, then ISO-8859-1, the encoding the pages declare
    /// (`protocol-parser.md` §4.2).
    public func fetchText(_ url: URL) async throws -> String {
        guard let text = ProtocolText.decode(try await fetchData(url)) else {
            throw ProtocolParserError.undecodableBody
        }
        return text
    }
}

/// The production fetcher: a plain GET with caching disabled (the pages send `no-cache`).
///
/// A `file:` URL is read from disk instead — the protocol may have been picked out of the file
/// system as a saved page or PDF, and its judge-detail link then resolves to a sibling file
/// (`protocol-parser.md` §8.2).
public struct URLSessionProtocolFetcher: ProtocolFetching {
    public init() {}

    public nonisolated func fetchData(_ url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProtocolParserError.fetchFailed(statusCode: http.statusCode)
        }
        return data
    }
}

/// Body decoding for the HTML path.
nonisolated enum ProtocolText {
    /// UTF-8 first, then ISO-8859-1 — the pages declare `charset=iso-8859-1`
    /// (`protocol-parser.md` §4.2).
    static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
