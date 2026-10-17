//
//  Log.swift
//  TechnicalOverlay
//
//  The app's logging: one subsystem, a category per area.
//

import os

/// Where the app writes.
///
/// One subsystem (the bundle id) and a category per part of the app, so Xcode's console and
/// Console.app can be filtered to the area being looked at instead of read as a wall of `print`.
/// Errors are `.error` (persisted), routine events `.debug` (streamed while debugging only).
enum Log {

    static let subsystem = "org.cjas.technical-overlay"

    /// The scoring document: autosave, decode, the `.tojson` pickers.
    static let data = Logger(subsystem: subsystem, category: "data")

    /// The loaded video: security scope, size probe, preview composition, the movie picker.
    static let media = Logger(subsystem: subsystem, category: "media")

    /// Save Video: chunk progress, stitching, export failures.
    static let export = Logger(subsystem: subsystem, category: "export")
}
