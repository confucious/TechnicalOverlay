//
//  Isu2026TechnicalPaneView.swift
//  LayoutEngine
//

import UIKit

/// The ISU 2026 technical pane: the running total first, the element boxes last.
///
/// Five rows, top to bottom — skater name and running total, element name, base value with bonus, the
/// execution mark, then the element boxes. The broadcast graphic's leader row, flag and
/// `TECHNICAL SCORE` header are deliberately absent: this pane is only the current element's block.
///
/// The name row is not simply the first row of the block. It wears the leader row's look — blue
/// behind white text, with the running total in its own band — its text is one point larger than the
/// rows below it, its height is exactly what that text needs, it overhangs them to the right, and only
/// the chips' hairline separates it from them. The element box row has no background of its own, so the
/// boxes alone sit over the video.
public class Isu2026TechnicalPaneView: OverlayView {

    let totalRow = Isu2026RowView(
        rowColor: Color.isu2026NameRow,
        labelColor: Color.isu2026NameRowText,
        valueColor: Color.isu2026NameRowText
    )
    let elementNameRow = Isu2026RowView(rowColor: Color.isu2026ElementRow)
    let baseValueRow = Isu2026RowView(rowColor: Color.isu2026Row)
    let goeRow = Isu2026RowView(rowColor: Color.isu2026Row, valueColor: .white)
    let elementRow = ElementRowView(style: .isu2026)

    /// Whether the element box row is drawn. It is the pane's bottom row, so hiding it leaves the
    /// pane's height unused below the execution row rather than moving the rows up: the pane draws no
    /// background of its own, so the space is invisible.
    public var showsElementBox: Bool = true {
        didSet {
            guard showsElementBox != oldValue else { return }
            elementRow.isHidden = !showsElementBox
            setNeedsLayout()
        }
    }

    public init() {
        super.init(frame: CGRect(
            origin: .zero,
            size: CGSize(width: 100.0, height: 200.0)
        ))
        addSubview(totalRow)
        addSubview(elementNameRow)
        addSubview(baseValueRow)
        addSubview(goeRow)
        addSubview(elementRow)

        totalRow.labelWeight = .bold
        totalRow.showsValueDivider = true
        elementNameRow.labelWeight = .bold
        baseValueRow.labelText = "BASE VALUE:"
        goeRow.labelText = "EXECUTION:"
        elementRow.isHidden = !showsElementBox
    }

    public func update(from viewModel: TechnicalViewModel) {
        totalRow.labelText = viewModel.skaterName
        totalRow.valueText = viewModel.totalValue
        elementNameRow.labelText = viewModel.elementName
        baseValueRow.valueText = viewModel.baseValue
        goeRow.valueText = viewModel.goeValue
        goeRow.valueCellColor = viewModel.goeValue.first == "-"
            ? Color.isu2026Negative
            : Color.isu2026Positive
        elementRow.boxModes = viewModel.boxModes
        showsElementBox = viewModel.showsElementBox
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        // The name row's height is set by its extra point of text, so the pane's spare height is shared
        // by the text rows below it.
        let mainRowHeight = (bounds.size.height - Metrics.isu2026NameRowExtraHeight)
            * Metrics.isu2026MainRowPercent

        // The name row: taller by what its larger text needs, wider than the block, clear of it.
        totalRow.frame = CGRect(
            x: 0,
            y: 0,
            width: width * Metrics.isu2026NameRowWidthPercent,
            height: mainRowHeight + Metrics.isu2026NameRowExtraHeight
        )

        let blockTop = totalRow.frame.maxY + mainRowHeight * Metrics.isu2026NameRowGapPercent
        let rows = [elementNameRow, baseValueRow, goeRow]
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(
                x: 0,
                y: blockTop + mainRowHeight * CGFloat(index),
                width: width,
                height: mainRowHeight
            )
        }
        elementRow.frame = showsElementBox
            ? CGRect(
                x: 0,
                y: blockTop + mainRowHeight * CGFloat(rows.count),
                width: width,
                height: mainRowHeight * Metrics.isu2026BoxRowPercent
            )
            : .zero
    }
}
