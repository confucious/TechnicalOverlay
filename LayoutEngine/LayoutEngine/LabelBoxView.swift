//
//  LabelBoxView.swift
//  LayoutEngine
//
//  The boxed-label rig the pane rows are built from.
//

import UIKit

/// How one boxed label sits inside its row.
///
/// Both inset sets are multiples of `Metrics.borderPercent` × the row's height: `box` is the
/// background's inset from the row's bounds, `label` the label's inset inside the background —
/// horizontal first, then vertical (usually half a border).
struct LabelBoxGeometry {
    var box: (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) = (0, 0, 0, 0)
    var label: (horizontal: CGFloat, vertical: CGFloat) = (1, 0.5)
}

/// A background with one label inset inside it, sized in proportions of its own height so the row
/// scales with the overlay.
///
/// Every single-label row in the panes is one of these — the lower third's name line, the element
/// name, both halves of the score row and both of the total row — so the border arithmetic and the
/// font sizing live here instead of in each row.
class LabelBoxView: OverlayView {

    /// The background behind the label.
    let box = UIView()
    let label = UILabel()

    var geometry = LabelBoxGeometry() {
        didSet { setNeedsLayout() }
    }

    /// The label's font, from the label's own height.
    var font: (CGFloat) -> UIFont = { .boldSystemFont(ofSize: $0) } {
        didSet { setNeedsLayout() }
    }

    var textAlignment: NSTextAlignment = .center {
        didSet { label.textAlignment = textAlignment }
    }

    var textColor: UIColor = .white {
        didSet { label.textColor = textColor }
    }

    var boxColor: UIColor = .clear {
        didSet { box.backgroundColor = boxColor }
    }

    /// Which height the corner radius follows: the box's own, or the row's — the latter for a row that
    /// splits into boxes and derives the radius from the row's height.
    enum CornerRadiusSource {
        case box
        case row
    }

    var cornerRadiusSource: CornerRadiusSource = .box {
        didSet { setNeedsLayout() }
    }

    var cornerMask: Set<CornerDirection> = [.nw, .ne, .sw, .se] {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(box)
        box.addSubview(label)

        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.textColor = textColor
        label.textAlignment = textAlignment
        box.backgroundColor = boxColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Metrics.borderInset(for: bounds.height)
        let geometry = geometry

        box.frame = bounds.inset(by: UIEdgeInsets(
            top: inset * geometry.box.top,
            left: inset * geometry.box.left,
            bottom: inset * geometry.box.bottom,
            right: inset * geometry.box.right
        ))
        label.frame = box.bounds.insetBy(
            dx: inset * geometry.label.horizontal,
            dy: inset * geometry.label.vertical
        )
        label.font = font(Metrics.fontSize(for: label.bounds.height))
        let radiusSource: UIView = cornerRadiusSource == .row ? self : box
        box.cornerConfiguration = radiusSource.roundedCornerConfiguration(corners: cornerMask)
    }
}
