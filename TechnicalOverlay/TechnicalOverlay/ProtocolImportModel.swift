//
//  ProtocolImportModel.swift
//  TechnicalOverlay
//
//  Drives the "Import Protocol" flow on `ScoringListView`: validate what the user gave us, run the
//  importer, merge the result, report anything that went wrong.
//  Spec: docs/architecture/protocol-parser.md — §7.3 (the importer), §8.1 (the merge), §8.2 (flow).
//
//  A protocol reaches us one of two ways — an address, or a file picked out of the file system — and
//  in either case it may be an ijsLive results page or an ISU FS Manager PDF: the importer decides
//  from the bytes, so nothing here needs to know which one it is.
//

import Foundation
import Observation
import ProtocolParser

@Observable
final class ProtocolImportModel {
    /// The protocol page address the user pasted — either page kind will do; the importer follows a
    /// leaderboard page to its judge-detail page when that has been published.
    var urlString = ""

    /// True while the import is running, so the UI can disable the button and show progress.
    private(set) var isImporting = false

    /// The message to show when something went wrong; `nil` when the last import worked.
    var errorMessage: String?

    private let importer: ProtocolImporter

    init(importer: ProtocolImporter = ProtocolImporter()) {
        self.importer = importer
    }

    /// Imports the skater named in `data` from the address in `urlString` and merges their elements.
    func importElements(into data: OverlayData) async {
        guard let url = Self.url(from: urlString) else {
            errorMessage = "Enter the address of the protocol: the results page, the judge detail scores page, or a protocol PDF."
            return
        }

        await importElements(into: data) { [importer] name in
            try await importer.skater(named: name, at: url)
        }
    }

    /// Imports the skater named in `data` from a protocol file the user picked — an HTML page of
    /// either kind or a protocol PDF, saved to the file system.
    ///
    /// The file is read once and handed over as bytes, so the importer classifies it the same way it
    /// classifies a download. Its own URL is the base for a relative judge-detail link, which then
    /// resolves to a sibling file saved beside it.
    func importElements(fromFileAt url: URL, into data: OverlayData) async {
        let fileData: Data
        do {
            fileData = try Self.contents(of: url)
        } catch {
            Log.data.error("protocol file unreadable: \(String(describing: error), privacy: .public)")
            errorMessage = "That file could not be read. Pick the protocol page or PDF again."
            return
        }

        await importElements(into: data) { [importer] name in
            try await importer.skater(named: name, in: fileData, baseURL: url)
        }
    }

    /// The shared half of both entry points: the skater-name guard, the run, the merge, the message.
    ///
    /// The merge is index-keyed and timing-preserving: elements already on the timeline keep their
    /// `displayTime`, new elements are appended untimed, and anything past the protocol's element
    /// count is left alone (`protocol-parser.md` §8.1).
    private func importElements(
        into data: OverlayData,
        reading skater: (String) async throws -> ProtocolSkater
    ) async {
        let skaterName = data.skaterFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skaterName.isEmpty else {
            errorMessage = "Enter the skater's full name before importing."
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let imported = try await skater(skaterName)
            guard !imported.elements.isEmpty else {
                errorMessage = "No executed elements were found for \(imported.name)."
                return
            }
            data.merge(imported)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// An `http(s)` address, or `nil` — so a pasted word, a bare host or a `file:` URL is rejected
    /// with an explanation instead of being handed to the network.
    nonisolated static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host()?.isEmpty == false
        else { return nil }
        return url
    }

    /// The bytes of a file the user picked, read inside the access scope the picker granted.
    ///
    /// A missing scope is not an error: a URL that was never scoped (a temporary file, or a file the
    /// app already owns) reads without one, and the read itself reports what it cannot open.
    nonisolated static func contents(of url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}
