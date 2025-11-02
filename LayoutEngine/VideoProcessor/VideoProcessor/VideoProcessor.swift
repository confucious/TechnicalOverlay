//
//  VideoProcessor.swift
//  VideoProcessor
//
//  Created by Jerry Hsu on 10/12/25.
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

public struct Slide: Sendable {
    let image: CIImage
    public let startTime: CMTime
    
    public init(image: CIImage, startTime: CMTime) {
        self.image = image
        self.startTime = startTime
    }
}

enum Metrics {
    static let transitionTime = 0.75
}

public class VideoComposer {
    
    var asset: AVAsset
    var slides: [Slide]
    
    public init(asset: AVAsset, slides: [Slide]) {
        self.asset = asset
        self.slides = slides.sorted(by: { a, b in
            a.startTime < b.startTime
        })
    }
    
    public func setupComposition() async throws -> AVVideoComposition? {
        return try await AVVideoComposition.videoComposition(
            with: asset) { [slides] request in
                // find slide appropriate for the compositionTime
                let indexedSlide = slides.enumerated().last { (_, slide) in
                    return request.compositionTime >= slide.startTime
                }
                if let indexedSlide {
                    let index = indexedSlide.offset
                    let previousImage = index > 0 ? slides[index - 1].image : CIImage.clear
                    let slide = indexedSlide.element
//                    print("Found slide \(slide.startTime)")
                    let diff = request.compositionTime - slide.startTime
                    if diff <= CMTime(
                        seconds: Metrics.transitionTime,
                        preferredTimescale: 1000
                    ) {
                        let dissolve = CIFilter.dissolveTransition()
                        dissolve.inputImage = previousImage
                        dissolve.targetImage = slide.image
                        dissolve.time = Float(
                            diff.seconds / Metrics.transitionTime
                        )
                        request.finish(
                            with: dissolve.outputImage!
                                .composited(over: request.sourceImage),
                            context: nil
                        )
                    } else {
                        request.finish(
                            with: slide.image.composited(over: request.sourceImage),
                            context: nil
                        )
                    }
                } else {
                    request.finish(with: request.sourceImage, context: nil)
                }
            }
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
            print("The preset can't export the video to the output file type.")
            return nil
        }
        
        // Create and configure the export session.
        guard let exportSession = AVAssetExportSession(asset: asset,
                                                       presetName: preset) else {
            print("Failed to create export session.")
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
            print("export failed \(error)")
            return nil
        }
    }
    public struct ExportSession {
        let exportSession: AVAssetExportSession
        let outputUrl: URL
        let outputFileType: AVFileType
        public let exportState: any AsyncSequence<AVAssetExportSession.State, Never>
        
        init(
            exportSession: AVAssetExportSession,
            outputUrl: URL,
            outputFileType: AVFileType,
        ) {
            self.exportSession = exportSession
            self.outputUrl = outputUrl
            self.outputFileType = outputFileType
            self.exportState = exportSession.states(updateInterval: 0.1)
        }
        
        public func performExport() async {
            do {
                try await exportSession.export(to: outputUrl, as: outputFileType)
            } catch {
                print("export failed \(error)")
            }
        }
    }
}
