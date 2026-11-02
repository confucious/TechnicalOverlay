//
//  VideoOverlay.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/12/25.
//

import UIKit

public class VideoOverlay: OverlayView {
    public enum Mode: Hashable {
        case none
        case technicalPane(TechnicalViewModel)
        case lowerThirdPane(LowerThirdViewModel)
    }
    
    public var mode: Mode {
        didSet {
            configure()
        }
    }
    
    let technicalPane = IsuTechnicalPaneView()
    /// The classic pane's rows reordered — same components, palette and metrics.
    let technicalPaneClassic2 = IsuTechnicalPaneView(rowOrder: .totalFirst)
    let technicalPane2026 = Isu2026TechnicalPaneView()
    let lowerThird = IsuLowerThirdView()
    
    public init(mode: Mode) {
        self.mode = mode
        super.init(
            frame: CGRect(origin: .zero, size: CGSize(width: 1280, height: 720))
        )
        addSubview(technicalPane)
        addSubview(technicalPaneClassic2)
        addSubview(technicalPane2026)
        addSubview(lowerThird)
        backgroundColor = .clear
        alpha = 0.9
        configure()
    }
    
    func configure() {
        subviews.forEach { view in
            view.isHidden = true
        }
        switch mode {
        case .none:
            break
        case let .technicalPane(viewModel):
            switch viewModel.style {
            case .classic:
                technicalPane.update(from: viewModel)
                technicalPane.isHidden = false
            case .classic2:
                technicalPaneClassic2.update(from: viewModel)
                technicalPaneClassic2.isHidden = false
            case .isu2026:
                technicalPane2026.update(from: viewModel)
                technicalPane2026.isHidden = false
            }
        case let .lowerThirdPane(viewModel):
            lowerThird.update(from: viewModel)
            lowerThird.isHidden = false
            break
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.size.height
        let techOriginOffset = height * Metrics.overlayBorderPercent
        let techHeight = height * Metrics.techPaneHeightPercent
        let techWidth = techHeight * Metrics.techPaneAspectRatio
        let techOrigin = CGPoint(x: techOriginOffset, y: techOriginOffset)
        let classicFrame = CGRect(
            origin: techOrigin,
            size: CGSize(width: techWidth, height: techHeight)
        )
        technicalPane.frame = classicFrame
        // The reordered classic shares the classic pane's frame: only its rows move.
        technicalPaneClassic2.frame = classicFrame

        // The 2026 pane has one more row than the classic one, so it is taller at the same text size.
        let tech2026Height = height * Metrics.isu2026TechPaneHeightPercent
        let tech2026Width = tech2026Height * Metrics.isu2026TechPaneAspectRatio
        technicalPane2026.frame = CGRect(
            origin: techOrigin,
            size: CGSize(width: tech2026Width, height: tech2026Height)
        )
        
        let width = bounds.size.width
        let lowerThirdPadding = height * Metrics.overlayBorderPercent
        let lowerThirdHeight = height * Metrics.lowerThirdHeightPercent
        let lowerThirdWidth = lowerThirdHeight * Metrics.lowerThirdAspectRatio
        lowerThird.frame = CGRect(
            origin: CGPoint(
                x: (width - lowerThirdWidth) / 2,
                y: height - lowerThirdHeight - lowerThirdPadding
            ),
            size: CGSize(width: lowerThirdWidth, height: lowerThirdHeight)
        )
    }
    
    public func render(size: CGSize) -> CIImage {
        bounds = CGRect(origin: .zero, size: size)
        layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: size,
            format: format
        )
        let image = renderer.image { context in
            layer.render(in: context.cgContext)
        }
        return CIImage(image: image)!
    }
    
}
