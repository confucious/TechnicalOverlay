//
//  DefaultStitcher.swift
//  VideoProcessor
//
// Assembles rendered chunk files and source video segments into the final
// output video using AVAssetReader/AVAssetWriter with sample buffer copying.

import AVFoundation
import CoreImage
import Foundation

// MARK: - Stitcher

/// Assembles rendered chunk files and source video segments into the final
/// output video using `AVAssetReader`/`AVAssetWriter` with sample buffer copying.
///
/// Not `Sendable` — `AVAssetReader`/`AVAssetWriter` are not thread-safe, and
/// the stitcher runs sequentially.
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

        // 1. Validate: all chunks must be rendered and non-stale
        let valid = chunks.filter { chunk in
            switch chunk.type {
            case .noOverlay:
                return !chunk.isStale
            case .constant, .transition:
                return chunk.isRendered && !chunk.isStale
            }
        }

        // 2. Sort by timeRange.start (should already be sorted, but be safe)
        let sorted = valid.sorted { $0.timeRange.start < $1.timeRange.start }
        
        guard sorted.last?.timeRange.end == videoDuration else {
            print("Stitcher: last chunk did not reach the end of the video")
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
            var duration: CMTime? = nil
            
            if let sourceVideoTrack = videoTracks.first {
                // Create the composition track only once
                if compositionVideoTrack == nil {
                    guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw NSError(domain: "CompositorError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"])
                    }
                    compositionVideoTrack = track
                }
                
                duration = try await sourceVideoTrack.load(.timeRange).duration
                
                // Append the video to the end of the current video timeline
                try compositionVideoTrack?.insertTimeRange(timeRange, of: sourceVideoTrack, at: currentTime)
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
            }
            
            if let duration {
                currentTime = CMTimeAdd(currentTime, duration)
            }
        }

        // 4. Process each chunk in order
        for chunk in sorted {
            do {
                switch chunk.type {
                case .noOverlay:
                    guard let stitchingRange = chunk.stitchingTimeRange else { return nil }
                    try await copyFrom(
                        asset: sourceAsset,
                        timeRange: stitchingRange
                    )

                case .transition:
                    guard let chunkOutputURL = chunk.outputURL else { return nil }
                    guard let stitchingRange = chunk.stitchingTimeRange else { return nil }
                    let renderedAsset = AVURLAsset(url: chunkOutputURL)

                    let localRange = localTimeRange(
                        for: stitchingRange,
                        inChunk: chunk,
                        inAsset: renderedAsset
                    )
                    try await copyFrom(asset: renderedAsset, timeRange: localRange)

                case .constant:
                    guard let chunkOutputURL = chunk.outputURL else { return nil }
                    guard let stitchingRange = chunk.stitchingTimeRange else { return nil }
                    let renderedAsset = AVURLAsset(url: chunkOutputURL)

                    let localRange = localTimeRange(
                        for: stitchingRange,
                        inChunk: chunk,
                        inAsset: renderedAsset
                    )
                    try await copyFrom(asset: renderedAsset, timeRange: localRange)
                }
            } catch {
                print("Stitcher: copy failed for chunk \(chunk.id): \(error)")
                return nil
            }
        }

        // 3. Check if we actually have anything to export
        guard compositionVideoTrack != nil || compositionAudioTrack != nil else {
            throw NSError(domain: "CompositorError", code: -3, userInfo: [NSLocalizedDescriptionKey: "No valid video or audio tracks found in provided assets."])
        }
        
        // 4. Create an Export Session to write the composition to a file
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw NSError(domain: "CompositorError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session."])
        }
        
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
