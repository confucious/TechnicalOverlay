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
    let endTime: CMTime? // if nil, stays active until next startTime
    
    public init(image: CIImage, startTime: CMTime, endTime: CMTime? = nil) {
        self.image = image
        self.startTime = startTime
        self.endTime = endTime
    }
}

public class VideoComposer {
    
    var asset: AVAsset
    var slides: [Slide]
    
    public init(asset: AVAsset, slides: [Slide]) {
        self.asset = asset
        self.slides = slides.sorted(by: { a, b in
            a.startTime > b.startTime
        })
    }
    
    public func setupComposition() async throws -> AVVideoComposition {
        return try await AVVideoComposition.videoComposition(
            with: asset) { [slides] request in
                // find slide appropriate for the compositionTime
                let slide = slides.first { slide in
                    return slide.startTime >= request.compositionTime
                    && (slide.endTime ?? CMTime.positiveInfinity) < request.compositionTime
                }
                if let slide {
                    request.finish(
                        with: slide.image.composited(over: request.sourceImage),
                        context: nil
                    )
                } else {
                    request.finish(with: request.sourceImage, context: nil)
                }
            }
    }
}
