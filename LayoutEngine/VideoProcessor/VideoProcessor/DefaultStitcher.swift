//
//  DefaultStitcher.swift
//  VideoProcessor
//
// Assembles rendered chunk files and source video segments into the final
// output video by appending their tracks into a single AVMutableComposition,
// then hands back an export session for the caller to perform.

import AVFoundation
import CoreImage
import Foundation

// MARK: - Stitcher

/// Assembles rendered chunk files and source video segments into the final output video.
///
/// Every chunk is appended in order into one `AVMutableComposition` holding a single video
/// track and a single audio track, and the resulting export session is returned for the caller
/// to perform — no file is written here.
public final class DefaultStitcher {
    
    private let outputFileType: AVFileType
    
    
    public init(outputFileType: AVFileType = .mov) {
        self.outputFileType = outputFileType
    }
}

// MARK: - StitcherProtocol conformance

extension DefaultStitcher: StitcherProtocol {

    public func stitch(
        chunks: [Chunk],
        sourceAsset: AVAsset,
        videoDuration: CMTime,
        to outputURL: URL
    ) async throws -> VideoComposer.ExportSession? {

        // 1. Validate: every chunk must be in the plan, and every overlay chunk rendered
        let valid = chunks.filter(\.isValid)
        let staleCount = chunks.count(where: { $0.hasOverlay && !$0.isInPlan })
        let unrenderedCount = chunks.count(where: { $0.hasOverlay && $0.isInPlan && !$0.isRendered })
        Trace.log(.stitcher, "stitch: \(chunks.count) chunks in → \(valid.count) valid (\(staleCount) stale, \(unrenderedCount) unrendered dropped), target duration \(videoDuration.traceDescription)")

        // 2. Sort by timeRange.start (should already be sorted, but be safe)
        let sorted = valid.sorted { $0.timeRange.start < $1.timeRange.start }
        
        guard sorted.last?.timeRange.end == videoDuration else {
            Trace.log(.stitcher, "abort: chunks end at \(sorted.last?.timeRange.end.traceDescription ?? "nothing"), video is \(videoDuration.traceDescription)")
            return nil
        }

        let composition = AVMutableComposition()
        
        var currentTime = CMTime.zero
        
        // We will keep references to the composition tracks so we only create ONE video track and ONE audio track
        // regardless of how many source assets we have.
        var compositionVideoTrack: AVMutableCompositionTrack?
        var compositionAudioTrack: AVMutableCompositionTrack?
        
        func copyFrom(asset: AVAsset, timeRange: CMTimeRange) async throws {
            // --- HANDLE VIDEO ---
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            var appended = false
            
            if let sourceVideoTrack = videoTracks.first {
                // Create the composition track only once
                if compositionVideoTrack == nil {
                    guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw NSError(domain: "CompositorError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"])
                    }
                    compositionVideoTrack = track
                }
                
                // Append the video to the end of the current video timeline
                try compositionVideoTrack?.insertTimeRange(timeRange, of: sourceVideoTrack, at: currentTime)
                appended = true
            }
            
            // --- HANDLE AUDIO ---
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first {
                // Create the composition track only once
                if compositionAudioTrack == nil {
                    guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw NSError(domain: "CompositorError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio track"])
                    }
                    compositionAudioTrack = track
                }
                                
                // Append the audio to the end of the current audio timeline
                try compositionAudioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: currentTime)
                appended = true
            }
            
            // The composition timeline grows by the range we just appended — never by the source
            // track's own duration.
            if appended {
                currentTime = CMTimeAdd(currentTime, timeRange.duration)
            }
        }

        // 4. Process each chunk in order
        for chunk in sorted {
            let chunkTimer = TraceTimer()
            do {
                switch chunk.type {
                case .noOverlay:
                    guard let stitchingRange = chunk.stitchingTimeRange else {
                        Trace.log(.stitcher, "abort: \(chunk.traceID) noOverlay chunk has no stitching range")
                        return nil
                    }
                    Trace.log(.stitcher, "\(chunk.traceID) noOverlay → source \(stitchingRange.traceDescription)")
                    try await copyFrom(
                        asset: sourceAsset,
                        timeRange: stitchingRange
                    )

                case .transition, .constant:
                    guard let chunkOutputURL = chunk.outputURL else {
                        Trace.log(.stitcher, "abort: \(chunk.traceID) \(chunk.type.traceName) chunk has no rendered output")
                        return nil
                    }
                    guard let stitchingRange = chunk.stitchingTimeRange else {
                        Trace.log(.stitcher, "abort: \(chunk.traceID) \(chunk.type.traceName) chunk has no stitching range")
                        return nil
                    }
                    let renderedAsset = AVURLAsset(url: chunkOutputURL)

                    let localRange = localTimeRange(
                        for: stitchingRange,
                        inChunk: chunk,
                        inAsset: renderedAsset
                    )
                    Trace.log(.stitcher, "\(chunk.traceID) \(chunk.type.traceName) → \(chunkOutputURL.lastPathComponent), absolute \(stitchingRange.traceDescription) read as local \(localRange.traceDescription)")
                    try await copyFrom(asset: renderedAsset, timeRange: localRange)
                }
                Trace.log(.stitcher, "  \(chunk.traceID) appended in \(chunkTimer.elapsedDescription), composition at \(currentTime.traceDescription)")
            } catch {
                Trace.log(.stitcher, "copy failed for \(chunk.traceID) after \(chunkTimer.elapsedDescription): \(error)")
                return nil
            }
        }

        // 3. Check if we actually have anything to export
        guard compositionVideoTrack != nil || compositionAudioTrack != nil else {
            Trace.log(.stitcher, "abort: composition has no video or audio tracks")
            throw NSError(domain: "CompositorError", code: -3, userInfo: [NSLocalizedDescriptionKey: "No valid video or audio tracks found in provided assets."])
        }

        Trace.log(.stitcher, "composition assembled: \(currentTime.traceDescription) of media, video track \(compositionVideoTrack == nil ? "none" : "1"), audio track \(compositionAudioTrack == nil ? "none" : "1")")

        // 4. Create an Export Session to write the composition to a file
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            Trace.log(.stitcher, "abort: could not create the passthrough export session")
            throw NSError(domain: "CompositorError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session."])
        }

        Trace.log(.stitcher, "ready: passthrough export of \(currentTime.traceDescription) → \(outputURL.lastPathComponent) (.mp4)")

        return VideoComposer.ExportSession(
            exportSession: exportSession,
            outputUrl: outputURL,
            outputFileType: .mp4
        )
    }
}

// MARK: - Internal helpers

extension DefaultStitcher {

    /// Maps an absolute-time stitching range to a local time range within the rendered chunk file.
    ///
    /// The rendered chunk was exported with its `stitchingTimeRange` as the export time range.
    /// `AVAssetReader`'s `currentTime` produces composition times relative to the asset's start.
    /// For a rendered file created from source asset at absolute time 10–20, composition time 0
    /// corresponds to absolute time 10. So to extract absolute 15–20, we read from local 5–10.
    private func localTimeRange(
        for absoluteRange: CMTimeRange,
        inChunk chunk: Chunk,
        inAsset asset: AVAsset
    ) -> CMTimeRange {
        let chunkAbsoluteStart = chunk.timeRange.start.seconds

        // Local start = (absolute stitching start) - (chunk absolute start)
        let localStart = CMTime(
            seconds: absoluteRange.start.seconds - chunkAbsoluteStart,
            preferredTimescale: 1000
        )

        // Local duration = stitching duration (unchanged)
        let localDuration = absoluteRange.duration

        return CMTimeRange(start: localStart, duration: localDuration)
    }
}

// MARK: - WriterInputs

/// Holds references to the writer's video and audio inputs for sample buffer appending.
private struct WriterInputs {
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?
}
