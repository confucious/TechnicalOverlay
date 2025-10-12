//
//  ElementRowView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/10/25.
//

import UIKit

class ElementRowView: UIView {
    
    var boxModes: [ElementBoxView.Mode] = [] {
        didSet {
            configure()
        }
    }
    let backgroundView = UIView()
    
    init() {
        super.init(
            frame: CGRect(origin: .zero, size: CGSize(width: 0.0, height: 50.0))
        )
        addSubview(backgroundView)
        backgroundView.backgroundColor = Color.technicalBackground
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.size.height
        let inset = height * Metrics.boxBorderPercent
        let boxSize = height - inset
        backgroundView.subviews.enumerated().forEach { (index, view) in
            let offset = index != 0 ? -ElementBoxView.Metrics.borderWidth : 0
            view.frame = CGRect(
                origin: CGPoint(x: inset + (boxSize + offset) * CGFloat(index), y: inset),
                size: CGSize(width: boxSize, height: boxSize)
            )
        }
        backgroundView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: inset + (backgroundView.subviews.last?.frame.maxX ?? 0.0), height: height)
        )
    }
    
    func configure() {
        backgroundView.subviews.forEach { $0.removeFromSuperview() }
        boxModes.enumerated().forEach { (index, mode) in
            let view = ElementBoxView(mode: mode)
            backgroundView.addSubview(view)
        }
    }
}
