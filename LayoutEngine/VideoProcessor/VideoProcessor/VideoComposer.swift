//
//  VideoComposer.swift
//  VideoProcessor
//
//  The preview pipeline: the recipe the preview compositor reads, the compositor itself, and the
//  composer that publishes the recipe and builds the preview composition.
//

import AVFoundation
import CoreImage
import Foundation
import os

// MARK: - Preview compositor

/// Everything the preview compositor needs to draw a frame.
///
/// AVFoundation instantiates a custom compositor itself (`init()`), so the recipe is published here
/// by `setupComposition()` rather than handed to the instance. The app keeps exactly one preview
/// composition — and therefore one live compositor — at a time.
nonisolated struct PreviewRecipe: Sendable {
    var slides: [Slide] = []
    var preferredTransform: CGAffineTransform = .identity
    /// Supplied by `setupComposition()`: `Metrics` is main-actor isolated, and the recipe is read
    /// from the compositor's own thread.
    var transitionTime: CMTime = CMTime(seconds: 0.75, preferredTimescale: 1000)
}

/// `PreviewRecipe` is written from the main actor and read from the compositor's own thread.
private nonisolated final class PreviewRecipeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recipe = PreviewRecipe()

    var current: PreviewRecipe {
        get { lock.lock(); defer { lock.unlock() }; return recipe }
        set { lock.lock(); recipe = newValue; lock.unlock() }
    }
}

nonisolated private let previewRecipe = PreviewRecipeBox()

/// The **preview**'s frame applier — the compositor behind `setupComposition()`, which therefore
/// does not use `AVVideoComposition(applyingFiltersTo:applier:)`.
///
/// It owns the preview's compositing so that a cancelled frame request never blocks: frames are
/// composited synchronously in `startRequest`, and an interrupted request is dropped by never calling
/// `finish` on it. AVFoundation's own Core Image compositor waits for outstanding requests in its
/// cancel path, which stalls the main thread on a playhead drag — **do not** put the preview back on
/// the filter API (`docs/HISTORY.md` → *Playhead freeze*).
///
/// The recipe is the same Core Image program the chunk renderer runs, so the preview keeps matching
/// what the export writes out.
public final class PreviewVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public nonisolated var sourcePixelBufferAttributes: [String: any Sendable]? {
        // Advertise what a 1080p source can arrive in; the render context then converts to the
        // format asked for below instead of failing the composition.
        [kCVPixelBufferPixelFormatTypeKey as String: [
            Int(kCVPixelFormatType_32BGRA),
            Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]]
    }

    public nonisolated var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    public nonisolated func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    /// Returns immediately: a request that has been cancelled is simply never finished. Waiting here
    /// is what stalls the main thread on a playhead drag (`docs/HISTORY.md` → *Playhead freeze*).
    public nonisolated func cancelAllPendingVideoCompositionRequests() {}

    public nonisolated func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let trackID = request.sourceTrackIDs.first?.int32Value,
              let sourceFrame = request.sourceFrame(byTrackID: trackID),
              let destination = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: PreviewCompositorError.missingSourceFrame)
            return
        }

        let recipe = previewRecipe.current
        // A custom compositor is handed the raw source frame: the layer instruction's transform is
        // not applied for us, so the track's preferred orientation has to be baked in here.
        let oriented = CIImage(cvPixelBuffer: sourceFrame)
            .transformed(by: recipe.preferredTransform)
        let source = oriented.transformed(
            by: CGAffineTransform(
                translationX: -oriented.extent.origin.x,
                y: -oriented.extent.origin.y
            )
        )
        context.render(
            composited(source, at: request.compositionTime, recipe: recipe),
            to: destination
        )
        request.finish(withComposedVideoFrame: destination)
    }

    /// The slide that owns `time`, faded in from (or out to) the one before it while a transition
    /// is in progress — the same `OverlayComposite` program the chunk renderer runs.
    private nonisolated func composited(_ source: CIImage, at time: CMTime, recipe: PreviewRecipe) -> CIImage {
        let slides = recipe.slides
        let indexed = slides.enumerated().last { (_, slide) in time >= slide.startTime }
        guard let indexed else { return source }

        let index = indexed.offset
        let slide = indexed.element
        let elapsed = time - slide.startTime
        if elapsed <= recipe.transitionTime {
            return OverlayComposite.dissolve(
                from: index > 0 ? slides[index - 1].image : nil,
                to: slide.image,
                progress: elapsed.seconds / recipe.transitionTime.seconds,
                over: source
            )
        }
        return OverlayComposite.hold(slide.image, over: source)
    }
}

enum PreviewCompositorError: Error {
    case missingSourceFrame
}

// MARK: - Composer

/// Publishes the preview recipe and builds the preview composition.
///
/// The chunk renderer does not use this type — it builds its own composition through
/// `ChunkComposition` — so everything here is preview-specific.
public class VideoComposer {
    
    var asset: AVAsset
    var slides: [Slide]
    
    public init(asset: AVAsset, slides: [Slide]) {
        self.asset = asset
        self.slides = slides.sorted(by: { a, b in
            a.startTime < b.startTime
        })
    }
    
    /// Builds the **preview** composition — the one attached to the `AVPlayerItem`.
    ///
    /// Unlike the chunk renderer, this does **not** go through
    /// `AVVideoComposition(applyingFiltersTo:applier:)`: frames are composited by
    /// `PreviewVideoCompositor`, driven by the recipe published here. Do not put it back on the filter
    /// API (`docs/HISTORY.md` → *Playhead freeze*).
    public func setupComposition() async throws -> AVVideoComposition? {
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            Log.composition.error("No video track to compose for")
            return nil
        }
        let duration = try await asset.load(.duration)
        previewRecipe.current = PreviewRecipe(
            slides: slides,
            preferredTransform: (try? await videoTrack.load(.preferredTransform)) ?? .identity,
            transitionTime: CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
        )

        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.customVideoCompositorClass = PreviewVideoCompositor.self

        var instruction = AVVideoCompositionInstruction.Configuration()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.enablePostProcessing = false
        // `requiredSourceTrackIDs` is computed from the layer instructions, so the compositor is
        // only handed frames for this track if the track is declared here.
        instruction.layerInstructions = [
            AVVideoCompositionLayerInstruction(configuration: .init(assetTrack: videoTrack))
        ]
        configuration.instructions = [AVVideoCompositionInstruction(configuration: instruction)]
        return AVVideoComposition(configuration: configuration)
    }
    
    public func setupExport(
        withPreset preset: String = AVAssetExportPresetHighestQuality,
        toFileType outputFileType: AVFileType = .mov,
        atURL outputURL: URL
    ) async -> ExportSession? {
            
        // Check the compatibility of the preset to export the video to the output file type.
        guard await AVAssetExportSession.compatibility(ofExportPreset: preset,
                                                       with: asset,
                                                       outputFileType: outputFileType) else {
            Log.composition.error("The preset can't export the video to the output file type.")
            return nil
        }
        
        // Create and configure the export session.
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                       presetName: preset) else {
            Log.composition.error("Failed to create export session.")
            return nil
        }
        
        // Convert the video to the output file type and export it to the output URL.
        do {
            exportSession.videoComposition = try await setupComposition()
            return ExportSession(
                exportSession: exportSession,
                outputUrl: outputURL,
                outputFileType: outputFileType
            )
        } catch {
            Log.composition.error("export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
