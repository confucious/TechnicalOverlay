//
//  ProtocolImportModel.swift
//  TechnicalOverlay
//
//  Drives the "Import Protocol" flow on `ScoringListView`: validate what the user gave us, run the
//  importer, merge the result, report anything that went wrong.
//  Spec: docs/architecture/protocol-parser.md — §7.3 (the importer), §8.1 (the merge).
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

    /// Imports the skater named in `data` and merges their elements into it.
    ///
    /// The merge is index-keyed and timing-preserving: elements already on the timeline keep their
    /// `displayTime`, new elements are appended untimed, and anything past the protocol's element
    /// count is left alone (`protocol-parser.md` §8.1).
    func importElements(into data: OverlayData) async {
        guard let url = Self.url(from: urlString) else {
            errorMessage = "Enter the address of the protocol page (the results page or the judge detail scores page)."
            return
        }
        let skaterName = data.skaterFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skaterName.isEmpty else {
            errorMessage = "Enter the skater's full name before importing."
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let skater = try await importer.skater(named: skaterName, at: url)
            guard !skater.elements.isEmpty else {
                errorMessage = "No executed elements were found for \(skater.name)."
                return
            }
            data.merge(skater)
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
}
