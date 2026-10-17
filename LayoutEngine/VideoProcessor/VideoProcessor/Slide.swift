//
//  Slide.swift
//  VideoProcessor
//
//  One overlay image and when it starts; the dissolve length they share.
//

import AVFoundation
import CoreImage

public struct Slide: Sendable, Equatable {
    let image: CIImage?
    public let startTime: CMTime
    
    public init(image: CIImage?, startTime: CMTime) {
        self.image = image
        self.startTime = startTime
    }
}

public enum Metrics {
    public static let transitionTime = 0.75
}
