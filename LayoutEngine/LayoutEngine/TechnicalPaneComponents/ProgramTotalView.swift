//
//  ProgramTotalView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/11/25.
//

import UIKit

/// The skater's abbreviated name on the left and the running total on the right.
class ProgramTotalView: OverlayView {

    public var skaterName: String = "" {
        didSet {
            configure()
        }
    }
    
    public var totalValue: String = "" {
        didSet {
            configure()
        }
    }

    let nameBox = LabelBoxView(frame: .zero)
    let totalBox = LabelBoxView(frame: .zero)

    init() {
        super.init(frame: .zero)
        addSubview(nameBox)
        addSubview(totalBox)

        nameBox.geometry = LabelBoxGeometry(box: (1, 1, 1, 0.5), label: (1, 0.5))
        nameBox.cornerRadiusSource = .row
        nameBox.textAlignment = .left
        nameBox.boxColor = Color.nameBox

        totalBox.geometry = LabelBoxGeometry(box: (1, 0.5, 1, 1), label: (1, 0.5))
        totalBox.cornerRadiusSource = .row
        totalBox.textAlignment = .right
        totalBox.boxColor = Color.totalScore
        totalBox.font = { .monospacedDigitSystemFont(ofSize: $0, weight: .bold) }

        backgroundColor = Color.technicalBackground
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        nameBox.frame = CGRect(x: 0, y: 0, width: width * 0.75, height: bounds.size.height)
        totalBox.frame = CGRect(
            x: width * 0.75,
            y: 0,
            width: width * 0.25,
            height: bounds.size.height
        )
    }

    func configure() {
        nameBox.label.text = skaterName
        totalBox.label.text = totalValue
    }
}
