//
//  VideoOverlay.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/12/25.
//

import UIKit

public class VideoOverlay: UIView {
    public enum Mode {
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
    let lowerThird = IsuLowerThirdView()
    
    public init(mode: Mode) {
        self.mode = mode
        super.init(
            frame: CGRect(origin: .zero, size: CGSize(width: 1280, height: 720))
        )
        addSubview(technicalPane)
        addSubview(lowerThird)
        backgroundColor = .clear
        alpha = 0.9
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure() {
        subviews.forEach { view in
            view.isHidden = true
        }
        switch mode {
        case .none:
            break
        case let .technicalPane(viewModel):
            technicalPane.update(from: viewModel)
            technicalPane.isHidden = false
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
        technicalPane.frame = CGRect(
            origin: CGPoint(x: techOriginOffset, y: techOriginOffset),
            size: CGSize(width: techWidth, height: techHeight)
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
