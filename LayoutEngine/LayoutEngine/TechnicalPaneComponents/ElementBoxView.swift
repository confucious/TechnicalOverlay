//
//  ElementBoxView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/3/25.
//

import UIKit

public class ElementBoxView: UIView {
    public enum Mode {
        case unscored
        case positive
        case negative
        case neutral
    }
    
    enum Metrics {
        static let borderWidth: CGFloat = 1.0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var mode: Mode {
        didSet {
            configure()
        }
    }
    let boxView = UIView()
    
    init(mode: Mode = .unscored) {
        self.mode = mode
        super.init(frame: CGRect(x: 0.0, y: 0.0, width: 50, height: 50))
        addSubview(boxView)
        backgroundColor = .black
        configure()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        boxView.frame = CGRect(
            x: Metrics.borderWidth,
            y: Metrics.borderWidth,
            width: frame.width - 2 * Metrics.borderWidth,
            height: frame.height - 2 * Metrics.borderWidth
        )
    }
    
    func configure() {
        switch mode {
        case .unscored: boxView.backgroundColor = .lightGray
        case .neutral: boxView.backgroundColor = .darkGray
        case .positive: boxView.backgroundColor = Color.positive
        case .negative: boxView.backgroundColor = Color.negative
        }
    }
}
