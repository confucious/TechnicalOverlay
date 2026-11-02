//
//  ElementRowView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/10/25.
//

import UIKit

/// The row of element boxes. The classic pane draws them touching on a grey strip that hugs them;
/// the 2026 pane draws them spaced across a white row that fills the pane's width.
class ElementRowView: OverlayView {

    let style: ElementBoxView.Style

    var boxModes: [ElementBoxView.Mode] = [] {
        didSet {
            configure()
        }
    }
    let backgroundView = UIView()
    
    init(style: ElementBoxView.Style = .classic) {
        self.style = style
        super.init(
            frame: CGRect(origin: .zero, size: CGSize(width: 0.0, height: 50.0))
        )
        addSubview(backgroundView)
        switch style {
        case .classic: backgroundView.backgroundColor = Color.technicalBackground
        // The 2026 box row sits straight on the video: the boxes are the whole row.
        case .isu2026: backgroundView.backgroundColor = .clear
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.size.height
        switch style {
        case .classic:
            let inset = height * Metrics.boxBorderPercent
            let boxSize = height - inset
            backgroundView.subviews.enumerated().forEach { (index, view) in
                let offset = index != 0 ? -ElementBoxView.Metrics.borderWidth : 0
                view.frame = CGRect(
                    origin: CGPoint(x: inset + (boxSize + offset) * CGFloat(index), y: inset),
                    size: CGSize(width: boxSize, height: boxSize)
                )
            }
            backgroundView.frame = CGRect(
                origin: .zero,
                size: CGSize(width: inset + (backgroundView.subviews.last?.frame.maxX ?? 0.0), height: height)
            )

        case .isu2026:
            // The boxes are packed from the row's left inset with only a hairline between them, and
            // are as tall as the row allows. They shrink — and only then — if that many would not fit
            // across the row's width.
            let inset = height * Metrics.isu2026BoxInsetPercent
            let gapPercent = Metrics.isu2026BoxGapPercent
            let count = max(backgroundView.subviews.count, 1)
            let available = bounds.size.width - inset * 2
            let boxSize = min(
                height - inset * 2,
                available / (CGFloat(count) * (1 + gapPercent))
            )
            let pitch = boxSize * (1 + gapPercent)
            backgroundView.subviews.enumerated().forEach { (index, view) in
                view.frame = CGRect(
                    origin: CGPoint(x: inset + pitch * CGFloat(index), y: (height - boxSize) / 2),
                    size: CGSize(width: boxSize, height: boxSize)
                )
            }
            backgroundView.frame = bounds
        }
    }
    
    func configure() {
        backgroundView.subviews.forEach { $0.removeFromSuperview() }
        boxModes.enumerated().forEach { (index, mode) in
            let view = ElementBoxView(mode: mode, style: style)
            backgroundView.addSubview(view)
        }
        // The new boxes arrive with no frame, and the row's own size need not change, so layout has
        // to be asked for rather than assumed.
        setNeedsLayout()
    }
}
