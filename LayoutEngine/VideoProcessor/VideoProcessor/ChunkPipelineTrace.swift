//
//  ChunkPipelineTrace.swift
//  VideoProcessor
//
// Formatting helpers for the chunk-pipeline trace output.
//
// The pipeline traces with plain `print` (matching the rest of this module) through
// `Trace.log` so every line carries the same `[Area]` prefix and the console can be
// scanned or grepped by stage:
//
//   [ChunkQueue]     queueing: enqueue, what came back from the diff, drains, staleness
//   [ChunkRenderer]  per-chunk render (export of one time-limited segment)
//   [Stitcher]       per-chunk assembly into the final composition, then the export session
//
// Lines are written for a human reading one export end to end, so they're deliberately
// verbose (per-chunk). Nothing here is redacted or rate-limited: this is diagnostic output,
// not production telemetry.

import AVFoundation
import CoreImage
import Foundation

// MARK: - Trace entry point

enum Trace {

    /// Which pipeline stage a line came from. The raw value is the printed prefix.
    enum Area: String {
        case queue = "ChunkQueue"
        case renderer = "ChunkRenderer"
        case stitcher = "Stitcher"
    }

    /// Writes one trace line as `[Area] message`.
    static func log(_ area: Area, _ message: String) {
        print("[\(area.rawValue)] \(message)")
    }
}

// MARK: - Chunk formatting

extension Chunk {

    /// First 8 characters of the chunk id — enough to correlate queue/render/stitch lines
    /// without the full UUID noise.
    var traceID: String {
        String(id.uuidString.prefix(8))
    }

    /// `id type range` — the identity triple most trace lines start with.
    var traceLabel: String {
        "\(traceID) \(type.traceName) \(timeRange.traceDescription)"
    }
}

extension ChunkType {

    var traceName: String {
        switch self {
        case .noOverlay: return "noOverlay"
        case .constant: return "constant"
        case .transition: return "transition"
        }
    }
}

extension ChunkState {

    /// `pending` / `rendering` / `rendered(<file>)`.
    var traceName: String {
        switch self {
        case .pending: return "pending"
        case .rendering: return "rendering"
        case .rendered(let url): return "rendered(\(url.lastPathComponent))"
        }
    }
}

extension Array where Element == ChunkRegion {

    /// `3 noOverlay, 15 constant, 7 transition`
    var traceBreakdown: String {
        let counts = reduce(into: [String: Int]()) { $0[$1.type.traceName, default: 0] += 1 }
        return ["noOverlay", "constant", "transition"]
            .compactMap { name in counts[name].map { "\($0) \(name)" } }
            .joined(separator: ", ")
    }
}

// MARK: - Time formatting
extension CMTimeRange {

    /// Compact `start–end` in seconds, e.g. `12.500–24.000`. Falls back to raw seconds for
    /// non-numeric (indefinite/infinite) times, which is what an unbounded video duration
    /// produces.
    var traceDescription: String {
        guard start.isNumeric, end.isNumeric else {
            return "\(start.seconds)–\(end.seconds)"
        }
        return String(format: "%.3f–%.3f", start.seconds, end.seconds)
    }
}

extension CMTime {

    /// `12.500s`, or `indefinite` / `infinite` for non-numeric times.
    var traceDescription: String {
        isNumeric ? String(format: "%.3fs", seconds) : (isIndefinite ? "indefinite" : "infinite")
    }
}

// MARK: - Image formatting

extension Optional where Wrapped == CIImage {

    /// `none` / `image(1280×720)` — used for the endpoints of a transition chunk.
    var traceName: String {
        switch self {
        case .none:
            return "none"
        case .some(let image):
            let extent = image.extent
            if extent.isInfinite {
                return "image(infinite)"
            } else {
                return "image(\(Int(extent.width))×\(Int(extent.height)))"
            }
        }
    }
}

// MARK: - File size

/// `, 1.24 MB` when the file exists, empty string otherwise — appended to export lines.
func traceFileSize(at url: URL) -> String {
    guard
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let size = attributes[.size] as? Int
    else { return "" }
    return String(format: ", %.2f MB", Double(size) / 1_048_576)
}

// MARK: - Timing

/// Monotonic stopwatch for the `in <n>ms` tails on trace lines.
struct TraceTimer {

    private let start = ContinuousClock.now

    var elapsedMilliseconds: Int {
        let components = start.duration(to: .now).components
        return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }

    /// `842ms` below a second, `15.20s` above it.
    var elapsedDescription: String {
        let ms = elapsedMilliseconds
        return ms < 1000 ? "\(ms)ms" : String(format: "%.2fs", Double(ms) / 1000)
    }
}
