//
//  RegionPlan.swift
//  VideoProcessor
//
//  The plan: the video's timeline swept into overlay regions, and the diff that turns a new plan into
//  chunks while reusing what it can.
//

import AVFoundation
import CoreImage
import Foundation

// MARK: - Region

public nonisolated struct ChunkRegion: Sendable {
    public let identity: ContentIdentity
    public let timeRange: CMTimeRange
    public let type: ChunkType

    public init(identity: ContentIdentity, timeRange: CMTimeRange, type: ChunkType) {
        self.identity = identity
        self.timeRange = timeRange
        self.type = type
    }
}

// MARK: - Span

/// One stretch of the video and what is drawn over it.
///
/// This is the plan before it is keyed for the diff: `generateRegions` turns each span into a
/// `ChunkRegion` by adding the content identity the chunk diff compares, and the preview compositor
/// reads the spans directly. **Which slide owns a frame therefore has one definition**, shared by the
/// preview and the export.
public nonisolated struct OverlaySpan: Sendable {
    public let type: ChunkType
    public let timeRange: CMTimeRange

    public init(type: ChunkType, timeRange: CMTimeRange) {
        self.type = type
        self.timeRange = timeRange
    }
}

/// What is drawn over a source frame at one moment.
public nonisolated enum OverlayContent {
    /// The source frame passes through.
    case none
    /// `image` held (nil also passes the source through).
    case hold(CIImage?)
    /// Mid-dissolve, `progress` in 0…1.
    case dissolve(from: CIImage?, to: CIImage?, progress: Double)
}

nonisolated extension Array where Element == OverlaySpan {

    /// What is drawn at `time`.
    ///
    /// The spans are contiguous and sorted, so the one containing `time` is the answer: a
    /// `.transition` span resolves to a dissolve whose progress is how far into the span `time` is.
    public func content(at time: CMTime, transitionTime: CMTime) -> OverlayContent {
        guard let span = first(where: { time >= $0.timeRange.start && time < $0.timeRange.end }) else {
            return .none
        }
        switch span.type {
        case .noOverlay:
            return .none
        case .constant(let image):
            return .hold(image)
        case .transition(let from, let to):
            let elapsed = time - span.timeRange.start
            return .dissolve(
                from: from,
                to: to,
                progress: elapsed.seconds / transitionTime.seconds
            )
        }
    }
}

// MARK: - overlaySpans

/// The video's timeline swept into the stretches that carry an overlay, and the stretches that do not.
///
/// The spans are sorted, contiguous, and cover the whole video. **A transition always runs its full
/// `transitionTime`.** When slides are closer together than that, the next dissolve starts where the
/// previous one ended rather than being shortened or overlapped, so every slide is faded in over the
/// full length — the later slide's dissolve simply begins after its own start time.
public nonisolated func overlaySpans(
    slides: [Slide],
    videoDuration: CMTime,
    transitionTime: CMTime
) -> [OverlaySpan] {
    let wholeVideo = CMTimeRange(start: .zero, duration: videoDuration)
    guard !slides.isEmpty else {
        return [OverlaySpan(type: .noOverlay, timeRange: wholeVideo)]
    }

    let sorted = slides.sorted { $0.startTime < $1.startTime }
    var spans: [OverlaySpan] = []

    /// Appends the span covering `start..<end`, clipped to the video. A transition that begins
    /// within `transitionTime` of the end would otherwise run past `videoDuration`, and the plan is
    /// what the stitcher checks against the video's exact length (`DefaultStitcher.stitch`), so an
    /// overrun aborts the export. An entirely empty span adds nothing.
    func append(_ type: ChunkType, from start: CMTime, to end: CMTime) {
        let clippedStart = max(start, .zero)
        let clippedEnd = min(end, videoDuration)
        guard clippedEnd > clippedStart else { return }
        spans.append(OverlaySpan(
            type: type,
            timeRange: CMTimeRange(start: clippedStart, end: clippedEnd)
        ))
    }

    var cursor = CMTime.zero

    for (index, slide) in sorted.enumerated() {
        let slideStart = slide.startTime

        // Gap before this slide's transition starts → noOverlay
        if cursor < slideStart {
            append(.noOverlay, from: cursor, to: slideStart)
        }

        // Transition span, starting at the slide — or where the previous transition left off, when
        // the slides are closer together than `transitionTime`.
        let transitionStart = max(cursor, slideStart)
        let transitionEnd = transitionStart + transitionTime
        append(
            .transition(from: index > 0 ? sorted[index - 1].image : nil, to: slide.image),
            from: transitionStart,
            to: transitionEnd
        )
        cursor = transitionEnd

        // Constant span: from end of transition to next slide start (or video end)
        let nextSlideStart = (index + 1 < sorted.count) ? sorted[index + 1].startTime : videoDuration
        if cursor < nextSlideStart {
            append(slide.image.map { .constant($0) } ?? .noOverlay, from: cursor, to: nextSlideStart)
            cursor = nextSlideStart
        }
    }

    if spans.isEmpty {
        return [OverlaySpan(type: .noOverlay, timeRange: wholeVideo)]
    }

    return spans
}

// MARK: - generateRegions

public nonisolated func generateRegions(
    slides: [Slide],
    videoDuration: CMTime,
    transitionTime: CMTime
) -> [ChunkRegion] {
    overlaySpans(
        slides: slides,
        videoDuration: videoDuration,
        transitionTime: transitionTime
    ).map { span in
        ChunkRegion(
            identity: span.type.contentIdentity,
            timeRange: span.timeRange,
            type: span.type
        )
    }
}

// MARK: - diffRegionsIntoChunks

public nonisolated func diffRegionsIntoChunks(
    newRegions: [ChunkRegion],
    existingChunks: [Chunk]
) -> [Chunk] {
    guard !newRegions.isEmpty else {
        return existingChunks.map { chunk in
            var updated = chunk
            updated.stitchingTimeRange = nil
            return updated
        }
    }

    var reusedIDs: Set<UUID> = []
    var result: [Chunk] = []

    for region in newRegions {
        switch region.type {
        case .noOverlay:
            // noOverlay chunks are never reused — always create new
            let newChunk = Chunk(timeRange: region.timeRange, type: region.type, renderState: .pending)
            result.append(newChunk)

        case .transition:
            // Transition chunks require exact timeRange match
            var matchIndex: Int?
            for (i, chunk) in existingChunks.enumerated() {
                guard !reusedIDs.contains(chunk.id) else { continue }
                guard chunk.contentIdentity == region.identity else { continue }
                guard chunk.timeRange.start == region.timeRange.start &&
                      chunk.timeRange.duration == region.timeRange.duration else { continue }
                matchIndex = i
                break
            }

            if let idx = matchIndex {
                let chunk = existingChunks[idx]
                var updated = chunk
                updated.stitchingTimeRange = region.timeRange
                result.append(updated)
                reusedIDs.insert(chunk.id)
            } else {
                let newChunk = Chunk(timeRange: region.timeRange, type: region.type, renderState: .pending)
                result.append(newChunk)
            }

        case .constant:
            // Constant chunks can be reused for overlapping portions
            var matchIndex: Int?
            for (i, chunk) in existingChunks.enumerated() {
                guard !reusedIDs.contains(chunk.id) else { continue }
                guard chunk.contentIdentity == region.identity else { continue }
                let overlap = chunk.timeRange.intersection(region.timeRange)
                guard !overlap.isEmpty else { continue }
                matchIndex = i
                break
            }

            if let idx = matchIndex {
                let chunk = existingChunks[idx]
                let overlap = chunk.timeRange.intersection(region.timeRange)

                // If region extends before the overlap, create a new pending chunk
                if region.timeRange.start < overlap.start {
                    let gapDuration = overlap.start - region.timeRange.start
                    let gapRange = CMTimeRange(start: region.timeRange.start, duration: gapDuration)
                    let gapChunk = Chunk(timeRange: gapRange, type: region.type, renderState: .pending)
                    result.append(gapChunk)
                }

                // Reuse the existing chunk trimmed to the overlap. The chunk's own timeRange does not
                // change; only the region used for stitching does.
                var updated = chunk
                updated.stitchingTimeRange = overlap
                result.append(updated)
                reusedIDs.insert(chunk.id)

                // If region extends after the overlap, create a new pending chunk
                if overlap.end < region.timeRange.end {
                    let gapDuration = region.timeRange.end - overlap.end
                    let gapRange = CMTimeRange(start: overlap.end, duration: gapDuration)
                    let gapChunk = Chunk(timeRange: gapRange, type: region.type, renderState: .pending)
                    result.append(gapChunk)
                }
            } else {
                let newChunk = Chunk(timeRange: region.timeRange, type: region.type, renderState: .pending)
                result.append(newChunk)
            }
        }
    }

    // Mark unreused existing chunks as stale (stitchingTimeRange = nil)
    for chunk in existingChunks {
        if !reusedIDs.contains(chunk.id) && chunk.hasOverlay {
            var updated = chunk
            updated.stitchingTimeRange = nil
            result.append(updated)
        }
    }

    return result
}
