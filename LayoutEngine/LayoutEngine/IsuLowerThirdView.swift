//
//  IsuLowerThirdView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 9/28/25.
//


import UIKit

public struct LowerThirdViewModel: Hashable {
    public init(
        skaterName: String,
        leftText: String,
        centerText: String,
        rightText: String
    ) {
        self.skaterName = skaterName
        self.leftText = leftText
        self.centerText = centerText
        self.rightText = rightText
    }
    
    public let skaterName: String
    public let leftText: String
    public let centerText: String
    public let rightText: String
}

public class IsuLowerThirdView: OverlayView {

    let upperLine: UpperLineView
    let lowerLine: LowerLineView
    
    public var skaterName: String {
        get {
            upperLine.nameLabel.text ?? ""
        }
        set {
            upperLine.nameLabel.text = newValue
        }
    }

    public init() {
        upperLine = UpperLineView()
        lowerLine = LowerLineView()
        super.init(frame: .zero)
        addSubview(upperLine)
        addSubview(lowerLine)
        backgroundColor = Color.technicalBackground
    }
    
    public func update(from viewModel: LowerThirdViewModel) {
        skaterName = viewModel.skaterName
        lowerLine.centerLabel.text = viewModel.centerText
        lowerLine.leftLabel.text = viewModel.leftText
        lowerLine.rightLabel.text = viewModel.rightText
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        let upperRowHeight = bounds.size.height * 0.525
        let lowerRowHeight = bounds.size.height * 0.325
        let inset = bounds.size.height * 0.05
        upperLine.frame = CGRect(
            origin: CGPoint(x: inset, y: inset),
            size: CGSize(
                width: width - inset * 2,
                height: upperRowHeight
            )
        )
        lowerLine.frame = CGRect(
            origin: CGPoint(x: inset, y: upperLine.frame.maxY + inset),
            size: CGSize(
                width: width - inset * 2,
                height: lowerRowHeight
            )
        )
        cornerConfiguration = self.roundedCornerConfiguration()
    }
    
    /// The skater's name, on the blue box.
    class UpperLineView: LabelBoxView {

        var nameLabel: UILabel { label }

        init() {
            super.init(frame: .zero)
            boxColor = Color.nameBox
        }
    }
    
    /// Left / centre / right text on the dark line. The centre label is measured, and the other two
    /// fill the space beside it — or the centre takes the whole box when it would not fit.
    class LowerLineView: OverlayView {
        let centerLabel = UILabel()
        let leftLabel = UILabel()
        let rightLabel = UILabel()
        let backgroundView = UIView()

        init() {
            super.init(frame: .zero)
            addSubview(backgroundView)
            backgroundView.addSubview(centerLabel)
            centerLabel.numberOfLines = 1
            centerLabel.adjustsFontSizeToFitWidth = true
            centerLabel.textColor = .white
            centerLabel.textAlignment = .center

            backgroundView.addSubview(leftLabel)
            leftLabel.numberOfLines = 1
            leftLabel.adjustsFontSizeToFitWidth = true
            leftLabel.textColor = .white
            leftLabel.textAlignment = .left

            backgroundView.addSubview(rightLabel)
            rightLabel.numberOfLines = 1
            rightLabel.adjustsFontSizeToFitWidth = true
            rightLabel.textColor = .white
            rightLabel.textAlignment = .right

            backgroundView.backgroundColor = Color.bottomLine
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = Metrics.borderInset(for: bounds.height)
            backgroundView.frame = bounds
            let layoutRect = backgroundView.bounds.insetBy(dx: inset, dy: inset / 2)
            centerLabel.frame = layoutRect
            centerLabel.font = .boldSystemFont(ofSize: Metrics.fontSize(for: centerLabel.bounds.height))
            let width = layoutRect.width
            centerLabel.sizeToFit()
            if centerLabel.frame.width > width - inset * 2 {
                centerLabel.frame = layoutRect
                leftLabel.frame = .zero
                rightLabel.frame = .zero
            } else {
                let centerWidth = centerLabel.frame.width
                centerLabel.frame.origin.x = (backgroundView.bounds.width - centerWidth) / 2
                leftLabel.frame = CGRect(
                    origin: layoutRect.origin,
                    size: CGSize(
                        width: centerLabel.frame.minX - inset,
                        height: layoutRect.height
                    )
                )
                leftLabel.font = .boldSystemFont(ofSize: Metrics.fontSize(for: leftLabel.bounds.height))
                rightLabel.frame = CGRect(
                    origin: CGPoint(
                        x: centerLabel.frame.maxX + inset,
                        y: centerLabel.frame.origin.y
                    ),
                    size: CGSize(
                        width: width - inset - centerLabel.frame.maxX,
                        height: layoutRect.height
                    )
                )
                rightLabel.font = .boldSystemFont(ofSize: Metrics.fontSize(for: rightLabel.bounds.height))
            }
            backgroundView.cornerConfiguration = backgroundView.roundedCornerConfiguration()
        }
    }
}
