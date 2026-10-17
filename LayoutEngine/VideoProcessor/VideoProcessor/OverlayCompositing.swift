//
//  OverlayCompositing.swift
//  VideoProcessor
//
//  The overlay program itself — how an image lands on a source frame — and the composition builder
//  the chunk renderer exports through. The preview and the chunk renderer run the same program here,
//  rather than one copy each.
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Wraps a composited frame for `AVVideoComposition(applyingFiltersTo:applier:)`, which replaces the
/// deprecated `videoComposition(with:applyingCIFiltersWithHandler:)`. A nil `ciContext` asks the
/// compositor to use its own context.
nonisolated private func filteringResult(_ image: CIImage) -> AVCIImageFilteringResult {
    AVCIImageFilteringResult(resultImage: image, ciContext: nil)
}

// MARK: - The overlay program

/// The two ways an overlay lands on a source frame: held, or dissolved from one image into another.
///
/// `PreviewVideoCompositor` uses these (picking its slides by time), and `ChunkComposition` uses them
/// (given the endpoints directly), so the preview and the export cannot drift apart.
///
/// A nil image is **no overlay on that side**, never "nothing to draw": holding a nil image passes
/// the source frame through, and a nil side of a dissolve is a fully transparent image, so the slide
/// fades in from (and out to) the plain source.
enum OverlayComposite {

    /// `image` held over `source`; nil passes the source through unchanged.
    nonisolated static func hold(_ image: CIImage?, over source: CIImage) -> CIImage {
        guard let image else { return source }
        return image.composited(over: source)
    }

    /// `from` dissolved into `to` at `progress` over `source`. `progress` is clamped to 0…1, so a
    /// caller can pass `elapsed / transitionTime` before any transition has run.
    nonisolated static func dissolve(
        from: CIImage?,
        to: CIImage?,
        progress: Double,
        over source: CIImage
    ) -> CIImage {
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = from ?? CIImage.clear
        dissolve.targetImage = to ?? CIImage.clear
        dissolve.time = Float(min(max(progress, 0), 1))
        return dissolve.outputImage?.composited(over: source) ?? source
    }
}

// MARK: - Chunk composition

/// The `AVVideoComposition` that exports one chunk: a single overlay held for the chunk's range, or a
/// dissolve between two overlays starting at a given time.
///
/// The composition covers the whole asset — the caller's `AVAssetExportSession.timeRange` selects the
/// chunk — so the applier's `compositionTime` is on the asset's timeline and `transitionStart` is an
/// absolute time.
public struct ChunkComposition {

    private let asset: AVAsset

    public init(asset: AVAsset) {
        self.asset = asset
    }

    /// One overlay image held over the source for every frame.
    public func overlay(_ image: CIImage?) async throws -> AVVideoComposition {
        try await AVVideoComposition(applyingFiltersTo: asset) { request in
            filteringResult(OverlayComposite.hold(image, over: request.sourceImage))
        }
    }

    /// `from` dissolved into `to` starting at `transitionStart`, for `Metrics.transitionTime`, then
    /// `to` held for the remaining frames.
    public func transition(
        from: CIImage?,
        to: CIImage?,
        startingAt transitionStart: CMTime
    ) async throws -> AVVideoComposition {
        let transitionTime = CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
        return try await AVVideoComposition(applyingFiltersTo: asset) { request in
            guard from != nil || to != nil else {
                // Neither side carries an overlay — nothing to dissolve.
                return filteringResult(request.sourceImage)
            }
            let elapsed = request.compositionTime - transitionStart
            guard elapsed <= transitionTime else {
                return filteringResult(OverlayComposite.hold(to, over: request.sourceImage))
            }
            return filteringResult(OverlayComposite.dissolve(
                from: from,
                to: to,
                progress: elapsed.seconds / transitionTime.seconds,
                over: request.sourceImage
            ))
        }
    }
}
