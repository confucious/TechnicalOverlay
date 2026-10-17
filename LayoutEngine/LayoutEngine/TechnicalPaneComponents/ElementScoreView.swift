//
//  ElementScoreView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/11/25.
//

import UIKit

/// The element's base value on the left and its GOE on the right; the GOE box is green or red from the
/// value's sign.
class ElementScoreView: OverlayView {

    public var baseValue: String = "" {
        didSet {
            configure()
        }
    }
    
    public var goeValue: String = "" {
        didSet {
            configure()
        }
    }

    let baseValueBox = LabelBoxView(frame: .zero)
    let goeValueBox = LabelBoxView(frame: .zero)

    init() {
        super.init(frame: .zero)
        addSubview(baseValueBox)
        addSubview(goeValueBox)

        baseValueBox.geometry = LabelBoxGeometry(box: (1, 1, 1, 0.5), label: (1, 0.5))
        baseValueBox.cornerRadiusSource = .row
        baseValueBox.textAlignment = .left
        baseValueBox.boxColor = .darkGray
        baseValueBox.font = { .monospacedDigitSystemFont(ofSize: $0, weight: .bold) }

        goeValueBox.geometry = LabelBoxGeometry(box: (1, 0.5, 1, 1), label: (1, 0.5))
        goeValueBox.cornerRadiusSource = .row
        goeValueBox.textAlignment = .right
        goeValueBox.font = { .monospacedDigitSystemFont(ofSize: $0, weight: .bold) }

        backgroundColor = Color.technicalBackground
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        baseValueBox.frame = CGRect(x: 0, y: 0, width: width * 0.65, height: bounds.size.height)
        goeValueBox.frame = CGRect(
            x: width * 0.65,
            y: 0,
            width: width * 0.35,
            height: bounds.size.height
        )
    }

    func configure() {
        baseValueBox.label.text = "BASE VALUE \(baseValue)"
        goeValueBox.label.text = "GOE \(goeValue)"
        goeValueBox.boxColor = goeValue.first == "-" ? Color.negative : Color.positive
    }
}
