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
    let startTime: CMTime
    
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
                    print("Found slide \(slide.startTime)")
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
}
