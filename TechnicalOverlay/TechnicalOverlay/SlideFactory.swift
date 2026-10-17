//
//  SlideFactory.swift
//  TechnicalOverlay
//
//  The document read as overlays, and the images they need — rendered once and cached.
//

import CoreImage
import CoreMedia
import Foundation
import LayoutEngine
import VideoProcessor

/// One overlay to draw, and when it starts.
struct SlidePlan: Equatable {
    let mode: VideoOverlay.Mode
    let startTime: TimeInterval
}

extension OverlayData {

    /// The overlays this document shows, in order: the introduction slides, a fade-out after them, the
    /// scored elements with their running total, and a fade-out after those.
    ///
    /// A `.none` slide is a fade-out: it carries no image, so the overlay dissolves back to the source.
    func slidePlan() -> [SlidePlan] {
        var plan: [SlidePlan] = []

        /// Five seconds after the last overlay, so it fades out instead of holding until the video
        /// ends.
        func appendFadeOut() {
            guard let last = plan.last else { return }
            plan.append(SlidePlan(mode: .none, startTime: last.startTime + 5))
        }

        for introduction in introductionTexts {
            guard let displayTime = introduction.displayTime else { continue }
            plan.append(SlidePlan(
                mode: introduction.makeMode(skaterName: skaterFullName),
                startTime: displayTime
            ))
        }
        appendFadeOut()

        var cumulativeBoxModes: [ElementBoxView.Mode] = Array(repeating: .unscored, count: elementScores.count)
        var cumulativeScore = 0

        for (index, element) in elementScores.enumerated() {
            cumulativeBoxModes[index] = if element.baseValue == 0 {
                .neutral
            } else if element.goeValue >= 0 {
                .positive
            } else {
                .negative
            }
            cumulativeScore += element.baseValue + element.goeValue + element.bonusValue
            let mode = element.makeMode(
                skaterName: skaterAbbreviatedName,
                runningTotal: cumulativeScore,
                boxModes: cumulativeBoxModes,
                showsElementBox: showsElementBox
            )
            guard let displayTime = element.displayTime else { continue }
            plan.append(SlidePlan(mode: mode, startTime: displayTime))
        }
        appendFadeOut()

        return plan
    }
}

/// Renders the images a plan needs, once per size and overlay content.
///
/// The cache is keyed by `(size, mode)` and holds only what the current plan uses, so a timing edit —
/// which changes times, not modes — re-renders nothing, while an editing session that walks through
/// many modes cannot grow it without bound.
final class SlideFactory {

    private struct CacheKey: Hashable {
        let size: CGSize
        let mode: VideoOverlay.Mode
    }

    private var cache: [CacheKey: CIImage] = [:]

    func slides(from plan: [SlidePlan], size: CGSize) -> [Slide] {
        var live: Set<CacheKey> = []

        let slides = plan.map { step -> Slide in
            let startTime = CMTime(seconds: step.startTime, preferredTimescale: 1000)
            guard step.mode != .none else {
                return Slide(image: nil, startTime: startTime)
            }

            let key = CacheKey(size: size, mode: step.mode)
            live.insert(key)
            let image = cache[key] ?? render(step.mode, size: size)
            cache[key] = image
            return Slide(image: image, startTime: startTime)
        }

        // Keep only what this plan uses.
        cache = cache.filter { live.contains($0.key) }
        return slides
    }

    private func render(_ mode: VideoOverlay.Mode, size: CGSize) -> CIImage {
        VideoOverlay(mode: mode).render(size: size)
    }
}
