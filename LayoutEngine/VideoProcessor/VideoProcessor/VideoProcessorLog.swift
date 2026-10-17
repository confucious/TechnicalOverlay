//
//  VideoProcessorLog.swift
//  VideoProcessor
//
//  Where the module writes: one subsystem, a category per area.
//

import os

/// `VideoProcessor`'s log.
///
/// The chunk pipeline gets its own category so one export can be followed without the composition
/// setup's chatter beside it. `Error`s are persisted; trace lines are `.debug`, streamed while
/// debugging and not stored.
enum Log {

    static let subsystem = "org.cjas.technical-overlay.video-processor"

    /// Per-chunk pipeline tracing — `ChunkQueue`, `ChunkRenderer`, `Stitcher` (see `Trace`).
    static let chunkPipeline = Logger(subsystem: subsystem, category: "chunk-pipeline")

    /// Composition and export setup: no video track, an incompatible preset, an export failure.
    static let composition = Logger(subsystem: subsystem, category: "composition")
}
