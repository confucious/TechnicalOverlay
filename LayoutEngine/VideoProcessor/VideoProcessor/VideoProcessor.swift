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

public class VideoComposer {
    
    var asset: AVAsset
    var slides: [Slide]
    
    public init(asset: AVAsset, slides: [Slide]) {
        self.asset = asset
        self.slides = slides.sorted(by: { a, b in
            a.startTime > b.startTime
        })
    }
    
    public func setupComposition() async throws -> AVVideoComposition? {
        return try await AVVideoComposition.videoComposition(
            with: asset) { [slides] request in
                // find slide appropriate for the compositionTime
                let slide = slides.first { slide in
                    return request.compositionTime >= slide.startTime
                }
                if let slide {
                    print("Found slide \(slide.startTime)")
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
