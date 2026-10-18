//
//  ChunkQueue.swift
//  VideoProcessor
//
//  The actor that owns the plan and renders it, one chunk at a time, reporting progress.
//

import AVFoundation
import Foundation

/// Progress reported during chunk rendering.
public struct ChunkQueueProgress: Sendable {
    public let completed: Int
    public let total: Int

    /// True while any chunk is queued or being rendered — i.e. the background pipeline still has
    /// work to do. Drives a status indicator in the app (green when false, yellow when true).
    public let isRendering: Bool
}

public actor ChunkQueue {
    public var chunks: [Chunk] = []
    private let renderer: any ChunkRendererProtocol
    private let transitionTime: CMTime
    private var drainTask: Task<Void, Never>?
    private var progressCallback: (@Sendable (ChunkQueueProgress) -> Void)?

    public init(renderer: any ChunkRendererProtocol, transitionTime: CMTime) {
        self.renderer = renderer
        self.transitionTime = transitionTime
    }

    public func setProgressCallback(_ callback: @escaping @Sendable (ChunkQueueProgress) -> Void) {
        progressCallback = callback
    }

    public func enqueue(slides: [Slide], videoDuration: CMTime) {
        let newRegions = generateRegions(
            slides: slides,
            videoDuration: videoDuration,
            transitionTime: transitionTime
        )
        Trace.log(.queue, "enqueue: \(slides.count) slides, video \(videoDuration.traceDescription) → \(newRegions.count) regions (\(newRegions.traceBreakdown))")

        let previousCount = chunks.count
        chunks = diffRegionsIntoChunks(newRegions: newRegions, existingChunks: chunks)

        let toRender = chunks.count(where: { $0.needsRender })
        let reused = chunks.count(where: { $0.hasOverlay && $0.isInPlan && !$0.needsRender })
        let stale = chunks.count(where: { $0.hasOverlay && !$0.isInPlan })
        Trace.log(.queue, "enqueue: \(chunks.count) chunks (was \(previousCount)) → \(toRender) to render, \(reused) reused, \(stale) stale")

        for chunk in chunks where chunk.hasOverlay {
            let disposition: String
            if !chunk.isInPlan {
                disposition = "stale (not reused)"
            } else if chunk.needsRender {
                disposition = "new → pending"
            } else {
                disposition = "reused → \(chunk.renderState.traceName)"
            }
            Trace.log(.queue, "  \(chunk.traceLabel) stitch=\(chunk.stitchingTimeRange?.traceDescription ?? "none") \(disposition)")
        }

        // Tell observers immediately: the queue now has work, even before the first render starts.
        reportProgress()

        if drainTask == nil {
            Trace.log(.queue, "enqueue: queue idle, starting drain")
            drainTask = Task { [weak self] in
                await self?.drain()
                await self?.finishDrain()
            }
        } else {
            Trace.log(.queue, "enqueue: drain already running, it will pick these up")
        }
    }

    private func finishDrain() {
        drainTask = nil
    }

    public func markStale(where predicate: (Chunk) -> Bool) {
        var newlyStale = 0
        for i in chunks.indices {
            if predicate(chunks[i]) {
                if chunks[i].isInPlan { newlyStale += 1 }
                chunks[i].stitchingTimeRange = nil
            }
        }
        Trace.log(.queue, "markStale: \(newlyStale) newly stale of \(chunks.count) chunks (\(chunks.count(where: { !$0.isInPlan })) stale total)")
        reportProgress()
    }

    public func startRendering() async {
        await drain()
    }

    public func waitForCompletion() async {
        let pendingAtStart = chunks.count(where: { $0.needsRender })
        let timer = TraceTimer()
        if pendingAtStart > 0 {
            Trace.log(.queue, "waitForCompletion: waiting on \(pendingAtStart) pending chunks")
        }

        while !Task.isCancelled {
            // A drain started by enqueue() may still be rendering a chunk it has already dequeued, so
            // wait for it: the caller stitches as soon as we return.
            if let drainTask {
                Trace.log(.queue, "waitForCompletion: awaiting the in-flight drain")
                await drainTask.value
                continue
            }
            guard dequeueNextRenderable() != nil else { break }
            await drain()
        }

        if pendingAtStart > 0 {
            let renderable = chunks.count(where: { $0.hasOverlay && $0.isRendered && $0.isInPlan })
            Trace.log(.queue, "waitForCompletion: done in \(timer.elapsedDescription), \(renderable) rendered and in plan")
        }
    }

    public func validChunks() -> [Chunk] {
        let valid = chunks.filter(\.isValid)
        Trace.log(.queue, "validChunks: \(valid.count) of \(chunks.count) chunks valid — dropping \(chunks.count(where: { $0.hasOverlay && !$0.isInPlan })) stale, \(chunks.count(where: { $0.needsRender })) pending")
        return valid
    }

    /// Stops rendering and deletes what this queue has rendered.
    ///
    /// The queue owns those files: the renderer writes them, but only the queue knows which ones it
    /// asked for. A cancelled drain is awaited before the files go, so nothing is still exporting
    /// into one when it is removed.
    public func shutdown() async {
        drainTask?.cancel()
        await drainTask?.value
        drainTask = nil

        let renderedFiles = chunks.compactMap(\.outputURL)
        chunks = []
        for file in renderedFiles {
            try? FileManager.default.removeItem(at: file)
        }
        reportProgress()
    }

    // MARK: - Internal

    private func reportProgress() {
        let total = chunks.count(where: { $0.hasOverlay })
        let completed = chunks.count(where: {
            $0.hasOverlay && $0.isRendered
        })
        // Stale chunks are excluded: they have no stitching range, so the queue will never touch them
        // again.
        let isRendering = chunks.contains { chunk in
            chunk.hasOverlay && chunk.isInPlan
                && (chunk.renderState == .pending || chunk.renderState == .rendering)
        }
        progressCallback?(ChunkQueueProgress(
            completed: completed,
            total: total,
            isRendering: isRendering
        ))
    }

    private func drain() async {
        let pendingAtStart = chunks.count(where: { $0.needsRender })
        let drainTimer = TraceTimer()
        var rendered = 0
        var failed = 0
        if pendingAtStart > 0 {
            Trace.log(.queue, "drain: start, \(pendingAtStart) pending")
            reportProgress()
        }

        while !Task.isCancelled {
            guard let next = dequeueNextRenderable() else {
                break
            }
            Trace.log(.queue, "drain: dequeue \(next.traceLabel) stitch=\(next.stitchingTimeRange?.traceDescription ?? "none")")
            markChunkRenderState(next.id, state: .rendering)

            let chunkTimer = TraceTimer()
            if let outputURL = await renderer.render(next) {
                markChunkRendered(next.id, outputURL: outputURL)
                rendered += 1
                Trace.log(.queue, "drain: rendered \(next.traceID) in \(chunkTimer.elapsedDescription) → \(outputURL.lastPathComponent)")
            } else {
                markChunkStale(next.id)
                failed += 1
                Trace.log(.queue, "drain: render failed for \(next.traceID) after \(chunkTimer.elapsedDescription), marked stale")
            }
            reportProgress()
        }

        if pendingAtStart > 0 || rendered > 0 || failed > 0 {
            let stillPending = chunks.count(where: { $0.needsRender })
            Trace.log(.queue, "drain: done, \(rendered) rendered, \(failed) failed, \(stillPending) still pending in \(drainTimer.elapsedDescription)")
            reportProgress()
        }
    }

    private func dequeueNextRenderable() -> Chunk? {
        guard let index = chunks.firstIndex(where: { $0.needsRender })
        else { return nil }
        return chunks[index]
    }

    private func markChunkRenderState(_ id: UUID, state: ChunkState) {
        if let index = chunks.firstIndex(where: { $0.id == id }) {
            chunks[index].renderState = state
        }
    }

    private func markChunkStale(_ id: UUID) {
        if let index = chunks.firstIndex(where: { $0.id == id }) {
            chunks[index].stitchingTimeRange = nil
        }
    }

    private func markChunkRendered(_ id: UUID, outputURL: URL) {
        markChunkRenderState(id, state: .rendered(outputURL))
    }
}
