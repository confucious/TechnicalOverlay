//
//  AssetSession.swift
//  TechnicalOverlay
//
//  The loaded video's file access, and the metadata probed from it.
//

import AVFoundation
import CoreGraphics
import Foundation

/// The security scope a loaded video holds, plus the metadata the app probes from it.
///
/// The scope is started when a file is adopted and stopped when it is replaced or released.
/// `startAccessingSecurityScopedResource()` returns `false` for a URL that was never scoped, which is
/// not a failure worth stopping for — the app still reads the file.
final class AssetSession {

    private(set) var url: URL?

    /// The video's display size, cached for the life of the file: probing it costs two asset loads and
    /// every slide regeneration needs it.
    private(set) var videoSize: CGSize?

    /// Adopts `url`, releasing the access held for the previous file. `nil` releases and clears.
    func adopt(_ url: URL?) {
        if let previous = self.url {
            previous.stopAccessingSecurityScopedResource()
        }
        self.url = url
        videoSize = nil

        guard let url else { return }
        if !url.startAccessingSecurityScopedResource() {
            print("Failed to get security scope")
        }
    }

    /// The video track's natural size with its preferred transform applied, both dimensions positive —
    /// a rotation can make either one negative.
    func size(of asset: AVAsset) async -> CGSize? {
        if let videoSize {
            return videoSize
        }
        guard let tracks = try? await asset.load(.tracks),
              let videoTrack = tracks.first(where: { $0.mediaType == .video })
        else {
            print("Couldn't find video track")
            return nil
        }
        guard let naturalSize = try? await videoTrack.load(.naturalSize),
              let transform = try? await videoTrack.load(.preferredTransform)
        else {
            print("Couldn't load size or transform for video track")
            return nil
        }

        let size = naturalSize.applying(transform)
        let fixedSize = CGSize(width: abs(size.width), height: abs(size.height))
        videoSize = fixedSize
        return fixedSize
    }
}
