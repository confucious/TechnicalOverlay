//
//  ElementScoreView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/11/25.
//

import UIKit

class ElementScoreView: UIView {
    public enum GoeStyle {
        case positive
        case negative
    }
    
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
    
    let baseValueLabel = UILabel()
    let baseValueBackground = UIView()
    let goeValueLabel = UILabel()
    let goeValueBackground = UIView()
    
    init() {
        super.init(
            frame: CGRect(origin: .zero, size: CGSize(width: 100.0, height: 50.0))
        )
        addSubview(baseValueBackground)
        addSubview(goeValueBackground)
        baseValueBackground.addSubview(baseValueLabel)
        goeValueBackground.addSubview(goeValueLabel)

        baseValueLabel.numberOfLines = 1
        baseValueLabel.adjustsFontSizeToFitWidth = true
        baseValueLabel.textColor = .white
        baseValueLabel.textAlignment = .left
        baseValueBackground.backgroundColor = .darkGray

        goeValueLabel.numberOfLines = 1
        goeValueLabel.adjustsFontSizeToFitWidth = true
        goeValueLabel.textColor = .white
        goeValueLabel.textAlignment = .right
        
        backgroundColor = Color.technicalBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        let height = bounds.size.height
        let inset = height * Metrics.borderPercent
        baseValueBackground.frame = CGRect(
            origin: .zero,
            size: CGSize(width: width * 0.65, height: height)
        ).inset(by: .init(top: inset, left: inset, bottom: inset, right: inset/2))
        goeValueBackground.frame = CGRect(
            origin: CGPoint(x: width * 0.65, y: 0),
            size: CGSize(width: width * 0.35, height: height)
        ).inset(by: .init(top: inset, left: inset/2, bottom: inset, right: inset))
        baseValueLabel.frame = baseValueBackground.bounds
            .insetBy(dx: inset, dy: inset/2)
        goeValueLabel.frame = goeValueBackground.bounds
            .insetBy(dx: inset, dy: inset/2)

        baseValueLabel.font = UIFont
            .monospacedDigitSystemFont(
                ofSize: baseValueLabel.fontSize(),
                weight: .bold
            )
        goeValueLabel.font =
            .monospacedDigitSystemFont(
                ofSize: goeValueLabel.fontSize(),
                weight: .bold
            )
        
        baseValueBackground.cornerConfiguration = roundedCornerConfiguration()
        goeValueBackground.cornerConfiguration = roundedCornerConfiguration()
    }
    
    func configure() {
        baseValueLabel.text = "BASE VALUE \(baseValue)"
        
        goeValueLabel.text = "GOE \(goeValue)"
        goeValueBackground.backgroundColor = goeValue.first == "-"
        ? Color.negative
        : Color.positive
    }
}
