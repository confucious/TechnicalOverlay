//
//  ElementNameView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/11/25.
//

import UIKit

class ElementNameView: UIView {
    
    public var name: String = "" {
        didSet {
            configure()
        }
    }
    
    let elementLabel = UILabel()
    let elementBackground = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(elementBackground)
        elementBackground.addSubview(elementLabel)
        elementLabel.numberOfLines = 1
        elementLabel.adjustsFontSizeToFitWidth = true
        elementLabel.textColor = .white
        elementLabel.textAlignment = .center
        elementBackground.backgroundColor = .black
        backgroundColor = Color.technicalBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = bounds.size.height * Metrics.borderPercent
        elementBackground.frame = bounds
            .inset(
                by: .init(top: inset, left: inset, bottom: inset, right: inset)
            )
        elementLabel.frame = elementBackground.bounds.insetBy(dx: inset, dy: 0.0)
        elementLabel.font = .boldSystemFont(ofSize: elementLabel.fontSize())
        elementBackground.cornerConfiguration = elementBackground
            .roundedCornerConfiguration()
    }
    
    func configure() {
        elementLabel.text = name
    }
}

