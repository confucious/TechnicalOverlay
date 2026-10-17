//
//  ElementNameView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/11/25.
//

import UIKit

/// The element's name on the black box, which sits inside the row by one border on every side.
class ElementNameView: LabelBoxView {

    var name: String = "" {
        didSet {
            configure()
        }
    }

    init() {
        super.init(frame: .zero)
        geometry = LabelBoxGeometry(box: (1, 1, 1, 1), label: (1, 0))
        boxColor = .black
        backgroundColor = Color.technicalBackground
    }

    func configure() {
        label.text = name
    }
}
