//
//  OverlayStore.swift
//  TechnicalOverlay
//
//  The autosave: the whole document as JSON in `UserDefaults`.
//

import Foundation
import os

/// Where the app keeps the document between launches.
///
/// The whole model goes in as JSON under one key — the app has one document at a time, and the file
/// interchange format (`.tojson`, `OverlayDataDocument`) is the one meant for moving documents
/// around.
enum OverlayStore {

    /// The `UserDefaults` key the autosave lives under.
    static let key = "state"

    static func save(_ data: OverlayData) {
        guard let json = try? JSONEncoder().encode(data) else {
            Log.data.error("Couldn't serialize to save state")
            return
        }
        Log.data.debug("saved")
        UserDefaults.standard.set(json, forKey: key)
    }

    /// Loads the saved document into `data`, leaving it untouched when there is nothing to load.
    static func load(into data: OverlayData) {
        guard let stored = UserDefaults.standard.data(forKey: key) else {
            Log.data.debug("No saved state found.")
            return
        }
        guard let loaded = try? JSONDecoder().decode(OverlayData.self, from: stored) else {
            Log.data.error("Couldn't decode saved state")
            return
        }
        data.update(from: loaded)
        Log.data.debug("loaded")
    }
}

extension OverlayData {

    /// Writes the document to the autosave.
    func save() {
        OverlayStore.save(self)
    }

    /// Replaces the document's contents with the autosave, when there is one.
    func load() {
        OverlayStore.load(into: self)
    }
}
