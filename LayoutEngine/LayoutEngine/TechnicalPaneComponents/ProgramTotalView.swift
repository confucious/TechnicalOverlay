//
//  ProgramTotalView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/11/25.
//

import UIKit

class ProgramTotalView: UIView {
    
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
    
    let nameLabel = UILabel()
    let nameBackground = UIView()
    let totalLabel = UILabel()
    let totalBackground = UIView()
    
    init() {
        super.init(
            frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 50))
        )
        addSubview(nameBackground)
        nameBackground.addSubview(nameLabel)
        nameLabel.frame = nameBackground.bounds
        addSubview(totalBackground)
        totalBackground.addSubview(totalLabel)
        totalLabel.frame = totalBackground.bounds
        
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.textColor = .white
        nameLabel.textAlignment = .left
        nameBackground.backgroundColor = Color.nameBox
        
        totalLabel.numberOfLines = 1
        totalLabel.adjustsFontSizeToFitWidth = true
        totalLabel.textColor = .white
        totalLabel.textAlignment = .right
        totalBackground.backgroundColor = Color.totalScore
        
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
        nameBackground.frame = CGRect(
            origin: .zero,
            size: CGSize(width: width * 0.75, height: height)
        ).inset(by: .init(top: inset, left: inset, bottom: inset, right: inset/2))
        nameLabel.frame = nameBackground.bounds.insetBy(dx: inset, dy: inset/2)
        nameLabel.font = .boldSystemFont(ofSize: nameLabel.fontSize())
        totalBackground.frame = CGRect(
            origin: CGPoint(x: width * 0.75, y: 0.0),
            size: CGSize(width: width * 0.25, height: height)
        ).inset(by: .init(top: inset, left: inset/2, bottom: inset, right: inset))
        totalLabel.frame = totalBackground.bounds.insetBy(dx: inset, dy: inset/2)
        totalLabel.font =
            .monospacedDigitSystemFont(ofSize: totalLabel.fontSize(), weight: .bold)
        
        nameBackground.cornerConfiguration = roundedCornerConfiguration()
        totalBackground.cornerConfiguration = roundedCornerConfiguration()
    }
    
    func configure() {
        nameLabel.text = skaterName
        totalLabel.text = totalValue
    }
}
