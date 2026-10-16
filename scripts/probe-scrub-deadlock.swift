// probe-scrub-deadlock.swift
//
// A headless reproduction of the app's worst failure mode: the video freezes — beachball — while
// the playhead is dragged, because the main thread blocks inside `AVPlayerItem.currentTime`
// (AVKitCore's -[AVPlayerController updateAtMinMaxTime] polls it on every scrub tick) on a
// MediaToolbox lock that the composition pipeline holds.
//
// It reproduces the two ways that happens, without any UI and without the app:
//   1. plain drag        — the CIFilter composition's cancel path
//                          (`FigVideoCompositionProcessorSetPlaybackTimeRange` →
//                          `AVCoreImageFilterCustomVideoCompositor
//                            .cancelAllPendingVideoCompositionRequests` → `dispatch_group_wait`)
//                          wedges after ~2 seeks.
//   2. drag + export     — the same drag while `AVAssetExportSession` renders 2 s chunks back to
//                          back, which is what the app's `ChunkQueue` does while you scrub. Stalls
//                          the drag for >20 s at a time *only* when the player item carries a video
//                          composition.
//
// What each variant measured (macOS 27, 2026-10-15/16; `swiftc -swift-version 5
// -default-isolation MainActor`):
//
//   ci-drag                  the app's pre-fix preview          wedges after 2 seeks
//   ci-trivial               applier returns the source frame   wedges the same — it is the
//                                                                 composition type, not the filters
//   ci-eager                 preview pre-renders its frames    400/400 (the 2026-10-15 fix; still
//                                                                 stalls under a draining export)
//   custom-drag / shipped    preview composited by our own      400/400 on a plain drag; still stalls
//                            AVVideoCompositing                 under a draining export
//   none-drag / std-drag     no composition / plain             300/300 with the export running —
//                            AVMutableVideoComposition          the composed-frame path is the hazard
//   ci-serial                seeks awaited one at a time        400/400 (why *clicking* always worked)
//   std-catool               Core Animation overlay tool        raises on playback — not an option
//   shipped + `sep`          exporter with its own AVURLAsset   6/6 clean (3/4 stalls without it)
//   shipped + `pace`         ~0.6 s idle between chunk exports  clean 2/2
//   shipped + `soft`         CPU CIContext for the preview       clean 2/2
//
// Build and run (needs the 398 MB "Boston Open 2025.mov" that the app's own integration tests use —
// it is untracked):
//
//   swiftc -swift-version 5 -default-isolation MainActor \
//     scripts/probe-scrub-deadlock.swift -o /tmp/probe-scrub
//   /tmp/probe-scrub ci-drag export human      # wedges
//   /tmp/probe-scrub shipped export human sep  # clean
//
// It exits 0 when every seek lands, or 2 after sampling itself (with `/usr/bin/sample`, written to
// /tmp/probe_sample_<variant>.txt) when the drag stops making progress for 20 s — that sample is
// the debugging artefact: the main thread's stack and the compositor queue's stack are the whole
// story.
//
// The `Slide`/`Metrics` shims and the `PreviewVideoCompositor` copy below are deliberately verbatim
// from VideoProcessor.swift as it stood during this investigation; that compositor is *not* in the
// app (the shipped preview pre-renders frames instead — see the decision log, 2026-10-15/16).

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import QuartzCore

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ci-drag"
let alsoExport = CommandLine.arguments.contains("export")
/// Human-paced drag: ~5 seeks/second for a minute, instead of a 60 Hz hammer.
let humanPaced = CommandLine.arguments.contains("human")
/// Probe-only experiment: composite preview frames with a software Core Image context, so the
/// preview stops sharing GPU/render-task machinery with the chunk export.
let softwarePreview = CommandLine.arguments.contains("soft")
/// Probe-only experiment: idle between chunk exports instead of draining them back to back.
let pacedExport = CommandLine.arguments.contains("pace")
/// Probe-only experiment: let the exporter use its own AVURLAsset instead of sharing the player's
/// (the app's chunk renderer is handed the same asset the player item uses).
let separateExportAsset = CommandLine.arguments.contains("sep")
/// Probe-only experiment: render the preview composition at 15 fps instead of the source's rate,
/// so the preview's Core Image work stops competing with the chunk export frame for frame.
let coarsePreview = CommandLine.arguments.contains("coarse")
/// The 398 MB sample the app's integration tests use, resolved relative to this file so the probe
/// works from any checkout.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // scripts/
    .deletingLastPathComponent()   // repo root
let source = repositoryRoot.appendingPathComponent("TechnicalOverlay/TechnicalOverlay/Boston Open 2025.mov")


// MARK: - shims for the shipped code under test

struct Slide: Sendable {
    let image: CIImage?
    let startTime: CMTime
}

enum Metrics {
    static let transitionTime = 0.75
}

// MARK: - Preview compositor

/// Everything the preview compositor needs to draw a frame.
///
/// AVFoundation instantiates a custom compositor itself (`init()`), so the recipe is published here
/// by `setupComposition()` rather than handed to the instance. The app keeps exactly one preview
/// composition — and therefore one live compositor — at a time.
nonisolated struct PreviewRecipe: Sendable {
    var slides: [Slide] = []
    var preferredTransform: CGAffineTransform = .identity
    var transitionTime: CMTime = CMTime(seconds: Metrics.transitionTime, preferredTimescale: 1000)
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

/// The **preview**'s frame applier — the compositor behind `setupComposition()`, and the reason
/// `setupComposition()` no longer uses `AVVideoComposition(applyingFiltersTo:applier:)`.
///
/// That API's Core Image compositor (`AVCoreImageFilterCustomVideoCompositor`) deadlocks the app
/// while the user drags the playhead: every seek runs
/// `FigVideoCompositionProcessorSetPlaybackTimeRange` →
/// `AVCoreImageFilterCustomVideoCompositor.cancelAllPendingVideoCompositionRequests`, which blocks
/// in a `dispatch_group_wait` for the session's outstanding frame requests — executed as a barrier
/// on the compositor session's own serial queue, the very queue those requests need. MediaToolbox
/// holds its lock across that call, and AVKit polls `AVPlayerItem.currentTime` from the main thread
/// on every scrub tick, so the app parks in `__psynch_mutexwait` under
/// `-[AVPlayerController updateAtMinMaxTime]` and never comes back.
///
/// Pre-rendering the image the applier returns shrinks that window a lot — a headless 400-seek
/// repro wedges after two seeks lazily and survives all 400 that way — but not to nothing: with a
/// chunk export competing for the same pipeline a frame request can still outlive the gap between
/// two seeks, and the cancel then wedges exactly as before. Owning the compositor closes it for
/// good, because there is nothing to wait for: frames are composited synchronously in
/// `startRequest`, and an interrupted request is dropped by never calling `finish` on it.
///
/// The recipe is the same Core Image program the chunk renderer runs, so the preview keeps matching
/// what the export writes out.
public final class PreviewVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = softwarePreview
        ? CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
        : CIContext(options: [.cacheIntermediates: false])

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

    /// Deliberately does not wait for anything — waiting here is the bug this type exists to avoid.
    /// A request that has been cancelled is simply never finished.
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
    /// is in progress — the same program the chunk renderer runs, where a nil image means "no
    /// overlay on that side", not "nothing to render".
    private nonisolated func composited(_ source: CIImage, at time: CMTime, recipe: PreviewRecipe) -> CIImage {
        let slides = recipe.slides
        let indexed = slides.enumerated().last { (_, slide) in time >= slide.startTime }
        guard let indexed else { return source }

        let index = indexed.offset
        let slide = indexed.element
        let diff = time - slide.startTime
        if diff <= recipe.transitionTime {
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = (index > 0 ? slides[index - 1].image : nil) ?? CIImage.clear
            dissolve.targetImage = slide.image ?? CIImage.clear
            dissolve.time = Float(diff.seconds / recipe.transitionTime.seconds)
            return dissolve.outputImage?.composited(over: source) ?? source
        }
        guard let image = slide.image else { return source }
        return image.composited(over: source)
    }
}

enum PreviewCompositorError: Error {
    case missingSourceFrame
}
// MARK: - progress beacon

final class Beacon: @unchecked Sendable {
    func setValue(_ v: Int) { value = v }

    private let lock = NSLock()
    private var _value = 0
    private var _lastChange = Date()
    private var _stuck = false
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; _lastChange = Date(); lock.unlock() }
    }
    var stuck: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _stuck }
        set { lock.lock(); _stuck = newValue; lock.unlock() }
    }
    var idleSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(_lastChange)
    }
}

let beacon = Beacon()
let applierCalls = Beacon()
let frames = Beacon()
let seeksDone = Beacon()
let done = Beacon()
let exports = Beacon()

final class Watchdog: Thread {
    /// Longest stretch the drag loop went without making progress, so a slow stall and a hard
    /// deadlock can be told apart.
    private var previousIdle = 0.0

    override func main() {
        while true {
            Thread.sleep(forTimeInterval: 1)
            if done.value > 0 { return }
            let idle = beacon.idleSeconds
            if idle > 2, previousIdle > 2, abs(idle - previousIdle) < 1.2 {
                print("[probe] stalled \(String(format: "%.1f", idle))s at seek \(beacon.value)")
            }
            previousIdle = idle
            if beacon.idleSeconds > 20 {
                beacon.stuck = true
                let pid = ProcessInfo.processInfo.processIdentifier
                let out = "/tmp/probe_sample_\(variant).txt"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                p.arguments = ["\(pid)", "3", "-file", out]
                try? p.run()
                p.waitUntilExit()
                print("[probe] STUCK: variant=\(variant) after \(beacon.value) seeks, applierCalls=\(applierCalls.value), frames=\(frames.value) — stacks: \(out)")
                Foundation.exit(2)
            }
        }
    }
}

// MARK: - composition builders

func filteringResult(_ image: CIImage) -> AVCIImageFilteringResult {
    AVCIImageFilteringResult(resultImage: image, ciContext: nil)
}

@MainActor
final class Composer {
    let asset: AVAsset
    let slides: [(CIImage, CMTime)]

    init(asset: AVAsset, slides: [(CIImage, CMTime)]) {
        self.asset = asset
        self.slides = slides
    }

    func ciComposition(trivial: Bool = false, eager: Bool = false) async throws -> AVVideoComposition? {
        let slides = self.slides
        return try await AVVideoComposition(applyingFiltersTo: asset) { request in
            applierCalls.value += 1
            let wrap: (CIImage) -> AVCIImageFilteringResult = { image in
                eager ? appFilteringResult(image, over: request.sourceImage) : filteringResult(image)
            }
            if trivial { return filteringResult(request.sourceImage) }
            let indexed = slides.enumerated().last { $0.element.1 <= request.compositionTime }
            guard let (index, (image, start)) = indexed.map({ ($0.offset, $0.element) }) else {
                return eager ? wrap(request.sourceImage) : filteringResult(request.sourceImage)
            }
            let diff = request.compositionTime - start
            if diff <= CMTime(seconds: 0.75, preferredTimescale: 1000) {
                let dissolve = CIFilter.dissolveTransition()
                dissolve.inputImage = index > 0 ? slides[index - 1].0 : CIImage.clear
                dissolve.targetImage = image
                dissolve.time = Float(diff.seconds / 0.75)
                return eager
                    ? wrap(dissolve.outputImage?.composited(over: request.sourceImage) ?? request.sourceImage)
                    : filteringResult(dissolve.outputImage?.composited(over: request.sourceImage) ?? request.sourceImage)
            }
            return eager ? wrap(image.composited(over: request.sourceImage))
                         : filteringResult(image.composited(over: request.sourceImage))
        }
    }

    func standardComposition(animationTool: Bool) async throws -> AVVideoComposition {
        let composition = try await AVMutableVideoComposition(propertiesOf: asset)
        if animationTool {
            let renderSize = composition.renderSize
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            let overlay = CALayer()
            overlay.frame = CGRect(x: 0, y: 0, width: renderSize.width, height: 200)
            overlay.backgroundColor = CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 0.85)
            let parent = CALayer()
            parent.frame = videoLayer.frame
            parent.isGeometryFlipped = true
            parent.addSublayer(videoLayer)
            parent.addSublayer(overlay)
            composition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parent
            )
        }
        return composition
    }


    /// Verbatim shape of VideoProcessor.swift's `setupComposition()`.
    func shippedComposition() async throws -> AVVideoComposition? {
        guard let videoTrack = try await asset.load(.tracks).first(where: { $0.mediaType == .video }) else {
            return nil
        }
        let duration = try await asset.load(.duration)
        previewRecipe.current = PreviewRecipe(
            slides: slides.map { Slide(image: $0.0, startTime: $0.1) },
            preferredTransform: (try? await videoTrack.load(.preferredTransform)) ?? .identity
        )
        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.customVideoCompositorClass = PreviewVideoCompositor.self
        if coarsePreview {
            configuration.frameDuration = CMTime(value: 1, timescale: 15)
        }
        var instruction = AVVideoCompositionInstruction.Configuration()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.enablePostProcessing = false
        instruction.layerInstructions = [
            AVVideoCompositionLayerInstruction(configuration: .init(assetTrack: videoTrack))
        ]
        configuration.instructions = [AVVideoCompositionInstruction(configuration: instruction)]
        return AVVideoComposition(configuration: configuration)
    }

    func customComposition() async throws -> AVVideoComposition {
        let composition = try await AVMutableVideoComposition(propertiesOf: asset)
        composition.customVideoCompositorClass = ProbeVideoCompositor.self
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            return composition
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        // requiredSourceTrackIDs is computed from the layer instructions, so the track has to be
        // declared here for the compositor to be handed its frames.
        instruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)]
        composition.instructions = [instruction]
        return composition
    }
}

// MARK: - our own compositor (candidate fix: Core Image frames, but cancellation is ours)

let probeOverlay = CIImage(color: CIColor(red: 0.0, green: 0.2, blue: 0.8))
    .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))

nonisolated(unsafe) let probeContext = CIContext(options: [.cacheIntermediates: false])
nonisolated let probeSourceAttributes: [String: any Sendable] = [
    kCVPixelBufferPixelFormatTypeKey as String: [Int(kCVPixelFormatType_32BGRA),
                                                 Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
]
nonisolated let probeRequiredAttributes: [String: any Sendable] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
]

final class ProbeVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    nonisolated var sourcePixelBufferAttributes: [String: any Sendable]? { probeSourceAttributes }
    nonisolated var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { probeRequiredAttributes }

    nonisolated func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    nonisolated func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        applierCalls.value += 1
        guard let trackID = request.sourceTrackIDs.first?.int32Value,
              let source = request.sourceFrame(byTrackID: trackID),
              let destination = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: NSError(domain: "probe", code: 1))
            return
        }
        probeContext.render(probeOverlay.composited(over: CIImage(cvPixelBuffer: source)), to: destination)
        if applierCalls.value == 1 || applierCalls.value % 200 == 0 {
            print("[probe] custom compositor wrote \(pixelProbe(destination))")
        }
        request.finish(withComposedVideoFrame: destination)
    }

    /// Nothing to wait for: dropped requests simply never call finish(). This is the whole point —
    /// AVFoundation's built-in Core Image compositor blocks here instead.
    nonisolated func cancelAllPendingVideoCompositionRequests() {}
}

/// Verbatim from VideoProcessor.swift's `filteringResult(_:over:)`, so the probe exercises the
/// shipped implementation and not a lookalike.
nonisolated private let previewFilterContext = CIContext()

nonisolated private func appFilteringResult(
    _ image: CIImage,
    over source: CIImage
) -> AVCIImageFilteringResult {
    let extent = source.extent.isInfinite ? image.extent : source.extent
    guard !extent.isInfinite, extent.width > 0, extent.height > 0,
          let rendered = previewFilterContext.createCGImage(image, from: extent)
    else {
        return filteringResult(image)
    }
    return filteringResult(
        CIImage(cgImage: rendered)
            .transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    )
}

func pixelProbe(_ buffer: CVPixelBuffer) -> String {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return "n/a" }
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let top = base.advanced(by: 10 * rowBytes + 10 * 4).assumingMemoryBound(to: UInt8.self)
    let bottom = base.advanced(by: (height - 10) * rowBytes + 10 * 4).assumingMemoryBound(to: UInt8.self)
    return "top(b=\(top[0]) g=\(top[1]) r=\(top[2])) bottom(b=\(bottom[0]) g=\(bottom[1]) r=\(bottom[2]))"
}

// MARK: - the drag

@MainActor
func run() async throws {
    let asset = AVURLAsset(url: source)
    var slides: [(CIImage, CMTime)] = []
    for i in 0..<40 {
        let color = CIColor(red: CGFloat(i % 3) / 3.0, green: 0.2, blue: 0.8)
        let overlay = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        slides.append((overlay, CMTime(seconds: Double(i) * 3.0, preferredTimescale: 600)))
    }
    let composer = Composer(asset: asset, slides: slides)

    var composition: AVVideoComposition?
    var exactSeek = true
    var gap: Double = 0.016
    var burst = 400
    switch variant {
    case "none-drag":
        composition = nil
    case "std-drag":
        composition = try await composer.standardComposition(animationTool: false)
    case "std-catool":
        composition = try await composer.standardComposition(animationTool: true)
    case "ci-trivial":
        composition = try await composer.ciComposition(trivial: true)
    case "ci-eager", "ci-eager-both":
        composition = try await composer.ciComposition(eager: true)
    case "shipped":
        composition = try await composer.shippedComposition()
    case "custom-drag":
        composition = try await composer.customComposition()
    case "ci-serial":
        composition = try await composer.ciComposition()
        exactSeek = true
        gap = 0
        burst = 60
    case "ci-click":
        composition = try await composer.ciComposition()
        gap = 1.5
        burst = 5
    case "ci-tolerance":
        composition = try await composer.ciComposition()
        exactSeek = false
        gap = 0.016
        burst = 400
    default:
        composition = try await composer.ciComposition()
    }

    let item = AVPlayerItem(asset: asset)
    item.videoComposition = composition
    let player = AVPlayer(playerItem: item)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ])
    item.add(output)

    // Background chunk export: the app's ChunkQueue renders with an AVAssetExportSession on the
    // *same* AVURLAsset the player item uses, so reproduce exactly that.
    if alsoExport {
        let chunkComposition: AVVideoComposition?
        switch variant {
        case "custom-drag":
            chunkComposition = try await composer.customComposition()
        case "shipped":
            chunkComposition = try await composer.ciComposition()
        case "ci-eager-both":
            chunkComposition = try await composer.ciComposition(eager: true)
        default:
            chunkComposition = try await composer.ciComposition()
        }
        let exportAsset: AVAsset = separateExportAsset ? AVURLAsset(url: source) : asset
        let exporter = Thread {
            var n = 0
            while !beacon.stuck && done.value == 0 {
                let out = FileManager.default.temporaryDirectory
                    .appendingPathComponent("probe_chunk_\(n % 4).mov")
                try? FileManager.default.removeItem(at: out)
                if let session = AVAssetExportSession(asset: exportAsset, presetName: AVAssetExportPresetHighestQuality) {
                    session.videoComposition = chunkComposition
                    session.outputURL = out
                    session.outputFileType = .mov
                    session.timeRange = CMTimeRange(
                        start: CMTime(seconds: Double(n) * 2, preferredTimescale: 600),
                        duration: CMTime(seconds: 2, preferredTimescale: 600)
                    )
                    let finished = DispatchSemaphore(value: 0)
                    let timer = Date()
                    session.exportAsynchronously { finished.signal() }
                    finished.wait()
                    print("[probe] chunk export \(n) done in \(String(format: "%.2f", Date().timeIntervalSince(timer)))s status=\(session.status.rawValue)")
                    exports.setValue(n + 1)
                }
                if pacedExport { Thread.sleep(forTimeInterval: 0.6) }
                n += 1
            }
        }
        exporter.stackSize = 1 << 21
        exporter.start()
    }

    let puller = Thread {
        while !beacon.stuck {
            let t = item.currentTime()
            var displayTime = CMTime.zero
            if let buffer = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: &displayTime) {
                frames.value += 1
                if frames.value % 60 == 0 {
                    print("[probe] \(variant) frame \(frames.value) top-left \(pixelProbe(buffer))")
                }
            }
            Thread.sleep(forTimeInterval: 0.008)
        }
    }
    puller.start()

    player.rate = 0
    try await Task.sleep(nanoseconds: 500_000_000)

    if humanPaced {
        gap = 0.2
        burst = 300
    }
    let start = 30.0
    var lastReported = Date()
    for i in 0..<burst {
        let t = CMTime(seconds: start + Double(i) * 0.25, preferredTimescale: 600)
        if variant == "ci-serial" {
            await player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if exactSeek {
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
        } else {
            let tol = CMTime(seconds: 0.5, preferredTimescale: 600)
            player.seek(to: t, toleranceBefore: tol, toleranceAfter: tol) { _ in }
        }
        _ = item.currentTime()
        beacon.value = i + 1
        if Date().timeIntervalSince(lastReported) > 1 {
            print("[probe] \(variant) seek \(i + 1)/\(burst) applierCalls=\(applierCalls.value) frames=\(frames.value) exports=\(exports.value)")
            lastReported = Date()
        }
        if gap > 0 { Thread.sleep(forTimeInterval: gap) }
    }

    seeksDone.value = burst
    print("[probe] OK: \(variant) \(burst) seeks landed, applierCalls=\(applierCalls.value), frames=\(frames.value)")
    beacon.value = burst
}

let watchdog = Watchdog()
watchdog.start()

Task { @MainActor in
    do { try await run() } catch { print("[probe] error \(error)") }
    done.value = 1
    Foundation.exit(0)
}
RunLoop.main.run()