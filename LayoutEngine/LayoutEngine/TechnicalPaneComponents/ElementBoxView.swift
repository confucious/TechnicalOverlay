//
//  ElementBoxView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 10/3/25.
//

import UIKit

public class ElementBoxView: OverlayView {
    public enum Mode {
        case unscored
        case positive
        case negative
        case neutral
    }

    /// The pane a box is drawn in. The two panes read the same modes with different palettes: the
    /// classic pane's unscored box is a filled grey, the 2026 pane's is an outlined white slot.
    public enum Style {
        case classic
        case isu2026
    }
    
    enum Metrics {
        static let borderWidth: CGFloat = 1.0
    }
    
    var mode: Mode {
        didSet {
            configure()
        }
    }

    let style: Style
    let boxView = UIView()
    
    init(mode: Mode = .unscored, style: Style = .classic) {
        self.mode = mode
        self.style = style
        super.init(frame: CGRect(x: 0.0, y: 0.0, width: 50, height: 50))
        addSubview(boxView)
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
        switch style {
        case .classic:
            backgroundColor = .black
            switch mode {
            case .unscored: boxView.backgroundColor = .lightGray
            case .neutral: boxView.backgroundColor = .darkGray
            case .positive: boxView.backgroundColor = Color.positive
            case .negative: boxView.backgroundColor = Color.negative
            }

        case .isu2026:
            backgroundColor = Color.isu2026BoxOutline
            switch mode {
            case .unscored: boxView.backgroundColor = Color.isu2026Unscored
            case .neutral: boxView.backgroundColor = Color.isu2026Neutral
            case .positive: boxView.backgroundColor = Color.isu2026Positive
            case .negative: boxView.backgroundColor = Color.isu2026Negative
            }
        }
    }
}
