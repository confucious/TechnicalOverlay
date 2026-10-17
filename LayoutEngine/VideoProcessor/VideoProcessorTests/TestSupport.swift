//
//  TestSupport.swift
//  VideoProcessorTests
//
//  Scaffolding shared by the integration suites.
//

import AVFoundation
import Foundation

/// The sample video the render and stitch suites run real exports against.
///
/// It is **untracked** — 398 MB is not going in the repo — so a suite that needs it returns early
/// when it is missing, and the run then proves less than it looks like it does
/// (`docs/testing.md` → *Prerequisites and known flakiness*).
let testVideoURL = URL(
    fileURLWithPath: "/Users/jhsu/dev/TechnicalOverlay/TechnicalOverlay/TechnicalOverlay/Boston Open 2025.mov"
)

/// The sample video as an asset, or `nil` when the fixture is not on this machine.
func makeTestAsset() -> AVAsset? {
    guard FileManager.default.fileExists(atPath: testVideoURL.path) else { return nil }
    return AVURLAsset(url: testVideoURL)
}
