//
//  Isu2026RowView.swift
//  LayoutEngine
//
//  One text row of the ISU 2026 technical pane.
//

import UIKit

/// A black label on the left and the value on the right, in the row's score column.
///
/// The value sits either on the row itself (the running total and the base value) or in a filled
/// cell at the row's right edge — the GOE row's green or red box, which is how the 2026 graphic
/// shows the sign. Both halves are `LabelBoxView`s, so the label insets and font sizing are the
/// same arithmetic the rest of the panes use.
class Isu2026RowView: OverlayView {

    /// The share of the row's width the value column takes. Every row in the pane uses it, so the
    /// values line up down the pane.
    static let valueColumnPercent = CGFloat(0.31)

    let labelBox = LabelBoxView(frame: .zero)
    let valueBox = LabelBoxView(frame: .zero)

    var labelText: String = "" {
        didSet { labelBox.label.text = labelText }
    }

    var valueText: String = "" {
        didSet { valueBox.label.text = valueText }
    }

    /// The cell filled behind the value. Clear means the value sits on the row, with the row's own
    /// background showing through.
    var valueCellColor: UIColor = .clear {
        didSet { valueBox.boxColor = valueCellColor }
    }

    /// The label's weight: bold for the rows that name something (the skater, the element), lighter
    /// for the `BASE VALUE:`/`EXECUTION:` captions.
    var labelWeight: UIFont.Weight = .semibold {
        didSet {
            let weight = labelWeight
            labelBox.font = { .systemFont(ofSize: $0, weight: weight) }
        }
    }

    /// The rule between the label and the value, which the broadcast leader row draws and the rows
    /// below it do not.
    var showsValueDivider: Bool = false {
        didSet { divider.isHidden = !showsValueDivider }
    }

    let divider = UIView()

    init(
        rowColor: UIColor,
        labelColor: UIColor = Color.isu2026Text,
        valueColor: UIColor = Color.isu2026Text
    ) {
        super.init(frame: .zero)
        addSubview(labelBox)
        addSubview(valueBox)
        addSubview(divider)
        divider.backgroundColor = Color.isu2026NameRowDivider
        divider.isHidden = !showsValueDivider
        backgroundColor = rowColor

        // Flush rows: the box fills the row and the label is inset by one border, horizontally.
        labelBox.geometry = LabelBoxGeometry(box: (0, 0, 0, 0), label: (1, 0.3))
        labelBox.cornerMask = []
        labelBox.textAlignment = .left
        labelBox.textColor = labelColor

        valueBox.geometry = LabelBoxGeometry(box: (0, 0, 0, 0), label: (1, 0.3))
        valueBox.cornerMask = []
        valueBox.textAlignment = .right
        valueBox.textColor = valueColor
        valueBox.font = { .monospacedDigitSystemFont(ofSize: $0, weight: .bold) }

        let weight = labelWeight
        labelBox.font = { .systemFont(ofSize: $0, weight: weight) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        let columnWidth = width * Self.valueColumnPercent
        labelBox.frame = CGRect(
            x: 0,
            y: 0,
            width: width - columnWidth,
            height: bounds.size.height
        )
        valueBox.frame = CGRect(
            x: width - columnWidth,
            y: 0,
            width: columnWidth,
            height: bounds.size.height
        )
        let dividerInset = Metrics.borderInset(for: bounds.size.height)
        divider.frame = CGRect(
            x: width - columnWidth,
            y: dividerInset,
            width: ElementBoxView.Metrics.borderWidth,
            height: bounds.size.height - dividerInset * 2
        )
    }
}
