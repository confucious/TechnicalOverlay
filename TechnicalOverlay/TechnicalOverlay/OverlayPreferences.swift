//
//  OverlayPreferences.swift
//  TechnicalOverlay
//

import Foundation

/// Device-level overlay settings, stored in `UserDefaults` so they survive a relaunch and apply to
/// every document. `OverlayData` carries the skater's scoring data; how the overlay is drawn is a
/// property of this device, so it does not travel in the `.tojson` file.
enum OverlayPreferences {

    enum Key {
        static let showsElementBox = "showsElementBox"
    }

    /// Boxes are shown unless the user has turned them off. An absent key means the default, so an
    /// unset preference has to be distinguished from a stored `false`.
    static var showsElementBox: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Key.showsElementBox) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showsElementBox)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showsElementBox)
        }
    }
}
