//
//  Chunk.swift
//  VideoProcessor
//
//  The unit of render work, its content identity, its state, and the pipeline's two seams.
//

import AVFoundation
import CoreImage
import Foundation

// MARK: - Content Identity

/// Stable identifier for chunk content independent of time range.
public struct ContentIdentity: Hashable, Sendable {
    public let kind: Kind
    public let hash: Int

    public enum Kind: Sendable {
        case noOverlay
        case constant
        case transition
    }

    public static func noOverlay() -> ContentIdentity {
        ContentIdentity(kind: .noOverlay, hash: 0)
    }

    public static func constant(image: CIImage) -> ContentIdentity {
        ContentIdentity(kind: .constant, hash: image.hashValue)
    }

    public static func transition(from: CIImage?, to: CIImage?) -> ContentIdentity {
        var hasher = Hasher()
        hasher.combine(from?.hashValue)
        hasher.combine(to?.hashValue)
        return ContentIdentity(kind: .transition, hash: hasher.finalize())
    }
}

// MARK: - Chunk Types

public enum ChunkType: Sendable, Equatable {
    case noOverlay
    case constant(CIImage)
    case transition(from: CIImage?, to: CIImage?)

    public var contentIdentity: ContentIdentity {
        switch self {
        case .noOverlay:
            return .noOverlay()
        case .constant(let image):
            return .constant(image: image)
        case .transition(let from, let to):
            return .transition(from: from, to: to)
        }
    }
}

public enum ChunkState: Sendable, Equatable {
    case pending
    case rendering
    case rendered(URL)
}

// MARK: - Chunk

public struct Chunk: Sendable {
    public let id: UUID
    public let timeRange: CMTimeRange
    public let type: ChunkType
    public let contentIdentity: ContentIdentity
    public var renderState: ChunkState
    public var stitchingTimeRange: CMTimeRange?

    public init(
        id: UUID = UUID(),
        timeRange: CMTimeRange,
        type: ChunkType,
        renderState: ChunkState = .pending
    ) {
        self.id = id
        self.timeRange = timeRange
        self.type = type
        self.contentIdentity = type.contentIdentity
        self.renderState = renderState
        self.stitchingTimeRange = timeRange
    }

    /// `true` for the chunks that carry an overlay — the only ones the queue renders and the
    /// stitcher copies from a rendered file.
    public var hasOverlay: Bool {
        type != .noOverlay
    }

    /// Whether the chunk is part of the current plan. `stitchingTimeRange` is the plan's own record
    /// of the range this chunk contributes: `diffRegionsIntoChunks` clears it to drop a chunk the
    /// new plan no longer covers (`markStale(where:)` does the same for a failed render).
    public var isInPlan: Bool {
        stitchingTimeRange != nil
    }

    /// Work the queue still owes this chunk: an overlay chunk with no render yet.
    public var needsRender: Bool {
        hasOverlay && renderState == .pending
    }

    /// Whether the chunk can be stitched: in the plan, and either rendered or an overlay-free range
    /// of the source. `ChunkQueue.validChunks()` and `DefaultStitcher.stitch` both filter on this.
    public var isValid: Bool {
        hasOverlay ? isRendered && isInPlan : isInPlan
    }

    public var isRendered: Bool {
        if !hasOverlay {
            // noOverlay chunks have no work to render, so they count as rendered.
            return true
        }
        if case .rendered = renderState {
            return true
        }
        return false
    }

    public var outputURL: URL? {
        if case .rendered(let url) = renderState { return url }
        return nil
    }
}

// MARK: - Protocols

public protocol ChunkRendererProtocol {
    func render(_ chunk: Chunk) async -> URL?
}

public protocol StitcherProtocol: Sendable {
    func stitch(
        chunks: [Chunk],
        sourceAsset: AVAsset,
        videoDuration: CMTime,
        to outputURL: URL
    ) async throws -> VideoComposer.ExportSession?
}
