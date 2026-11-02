//
//  LayoutEngineTests.swift
//  LayoutEngineTests
//
//  Created by Jerry Hsu on 9/21/25.
//

import Testing
import UIKit
@testable import LayoutEngine

struct LayoutEngineTests {

    private func makePane(showsElementBox: Bool) -> IsuTechnicalPaneView {
        let pane = IsuTechnicalPaneView()
        pane.frame = CGRect(x: 0.0, y: 0.0, width: 300.0, height: 120.0)
        pane.update(from: TechnicalViewModel(
            skaterName: "Jerry Hsu",
            elementName: "3Lz",
            baseValue: "5.90",
            goeValue: "0.50",
            totalValue: "6.40",
            boxModes: [.positive],
            showsElementBox: showsElementBox
        ))
        pane.setNeedsLayout()
        pane.layoutIfNeeded()
        return pane
    }

    @Test func elementBoxRowIsHiddenWhenTurnedOff() {
        let shown = makePane(showsElementBox: true)
        let hidden = makePane(showsElementBox: false)

        #expect(!shown.elementRow.isHidden)
        #expect(shown.elementRow.frame.height > 0)
        #expect(hidden.elementRow.isHidden)
        #expect(hidden.elementRow.frame == .zero)
    }

    @Test func rowsSitHigherWithoutElementBoxes() {
        let shown = makePane(showsElementBox: true)
        let hidden = makePane(showsElementBox: false)

        // The name row takes the box row's place, and the rows below it move up with it.
        #expect(hidden.elementNameView.frame.minY == 0)
        #expect(hidden.elementNameView.frame.minY < shown.elementNameView.frame.minY)
        #expect(hidden.elementScore.frame.minY < shown.elementScore.frame.minY)
        #expect(hidden.total.frame.maxY < shown.total.frame.maxY)
        // Only the box row's height is given up — the remaining rows keep their size.
        #expect(hidden.elementNameView.frame.height == shown.elementNameView.frame.height)
        #expect(hidden.total.frame.height == shown.total.frame.height)
    }

    @Test func paneFrameIsUnchangedWithoutElementBoxes() {
        let shown = makePane(showsElementBox: true)
        let hidden = makePane(showsElementBox: false)

        #expect(hidden.bounds == shown.bounds)
    }

    @Test func labelBoxInsetsItsBoxAndLabelInProportionToItsHeight() {
        let box = LabelBoxView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        box.geometry = LabelBoxGeometry(box: (1, 1, 1, 1), label: (1, 0.5))
        box.setNeedsLayout()
        box.layoutIfNeeded()

        let inset = 40 * Metrics.borderPercent
        #expect(box.box.frame == CGRect(
            x: inset,
            y: inset,
            width: 200 - inset * 2,
            height: 40 - inset * 2
        ))
        #expect(box.label.frame == box.box.bounds.insetBy(dx: inset, dy: inset / 2))
        // The font follows the label's height, not the row's.
        #expect(box.label.font.pointSize == Metrics.fontSize(for: box.label.bounds.height))
    }

    @Test func aFullBleedBoxKeepsOnlyTheLabelInset() {
        let box = LabelBoxView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        box.setNeedsLayout()
        box.layoutIfNeeded()

        #expect(box.box.frame == box.bounds)
        let inset = 40 * Metrics.borderPercent
        #expect(box.label.frame == CGRect(
            x: inset,
            y: inset / 2,
            width: 200 - inset * 2,
            height: 40 - inset
        ))
    }

    // MARK: - Classic 2 pane

    private func makeClassic2Pane(showsElementBox: Bool = true) -> IsuTechnicalPaneView {
        let pane = IsuTechnicalPaneView(rowOrder: .totalFirst)
        pane.frame = CGRect(x: 0.0, y: 0.0, width: 300.0, height: 120.0)
        pane.update(from: TechnicalViewModel(
            skaterName: "Jerry Hsu",
            elementName: "3Lz",
            baseValue: "5.90",
            goeValue: "0.50",
            totalValue: "6.40",
            boxModes: [.positive, .positive],
            showsElementBox: showsElementBox,
            style: .classic2
        ))
        pane.setNeedsLayout()
        pane.layoutIfNeeded()
        return pane
    }

    /// Classic 2 is the classic pane with the rows reordered: total first, boxes last.
    @Test func classic2StacksTheRunningTotalThroughTheElementBoxes() {
        let pane = makeClassic2Pane()
        let rows = [pane.total, pane.elementNameView, pane.elementScore, pane.elementRow]

        #expect(rows[0].frame.minY == 0)
        let borderSize = Metrics.borderInset(for: 120.0 * Metrics.mainRowPercent)
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            // One below the other, overlapping by the single border their backgrounds leave between
            // them — the classic pane's row spacing.
            #expect(lower.frame.minY > upper.frame.minY)
            #expect(abs((upper.frame.maxY - lower.frame.minY) - borderSize) < 0.5)
        }
    }

    /// Same components, same sizes, same pane — only the order changes.
    @Test func classic2KeepsTheClassicRowsAndSizes() {
        let classic = makePane(showsElementBox: true)
        let reordered = makeClassic2Pane(showsElementBox: true)

        #expect(reordered.bounds == classic.bounds)
        #expect(reordered.total.frame.size == classic.total.frame.size)
        #expect(reordered.elementNameView.frame.size == classic.elementNameView.frame.size)
        #expect(reordered.elementScore.frame.size == classic.elementScore.frame.size)
        #expect(reordered.elementRow.frame.size == classic.elementRow.frame.size)
    }

    @Test func classic2MovesTheRowsUpWhenTheBoxesAreHidden() {
        let pane = makeClassic2Pane(showsElementBox: false)

        #expect(pane.elementRow.isHidden)
        #expect(pane.elementRow.frame == .zero)
        #expect(pane.total.frame.minY == 0)
        #expect(pane.elementScore.frame.maxY < pane.bounds.height)
    }

    // MARK: - ISU 2026 pane

    private func make2026Pane(
        showsElementBox: Bool = true,
        goeValue: String = "0.50"
    ) -> Isu2026TechnicalPaneView {
        let pane = Isu2026TechnicalPaneView()
        pane.frame = CGRect(x: 0.0, y: 0.0, width: 330.0, height: 144.0)
        pane.update(from: TechnicalViewModel(
            skaterName: "Jerry Hsu",
            elementName: "3Lz",
            baseValue: "5.90",
            goeValue: goeValue,
            totalValue: "6.40",
            boxModes: [.positive, .positive, .unscored],
            showsElementBox: showsElementBox,
            style: .isu2026
        ))
        pane.setNeedsLayout()
        pane.layoutIfNeeded()
        return pane
    }

    /// The 2026 pane's order: running total first, element boxes last.
    @Test func pane2026StacksTheRunningTotalThroughTheElementBoxes() {
        let pane = make2026Pane()
        let block = [pane.elementNameRow, pane.baseValueRow, pane.goeRow, pane.elementRow]

        #expect(pane.totalRow.frame.minY == 0)
        for (upper, lower) in zip(block, block.dropFirst()) {
            #expect(abs(upper.frame.maxY - lower.frame.minY) < 0.5)
        }
        #expect(abs(pane.elementRow.frame.maxY - pane.bounds.height) < 0.5)
        // The box row is the shortest of the rows, and the block spans the pane's width.
        #expect(pane.elementRow.frame.height < pane.goeRow.frame.height)
        #expect(block.allSatisfy { $0.frame.width == pane.bounds.width })
    }

    /// The name row wears the leader row's look and stands apart from the block below it.
    @Test func pane2026DressesTheNameRowAsTheLeaderRow() {
        let pane = make2026Pane()
        let name = pane.totalRow
        let block = [pane.elementNameRow, pane.baseValueRow, pane.goeRow]

        #expect(name.backgroundColor == Color.isu2026NameRow)
        #expect(name.labelBox.label.textColor == Color.isu2026NameRowText)
        #expect(name.valueBox.label.textColor == Color.isu2026NameRowText)
        // One point larger than the rows below it, in a row taller by exactly what that needs.
        let nameFont = name.labelBox.label.font.pointSize
        let blockFont = pane.goeRow.labelBox.label.font.pointSize
        #expect(abs((nameFont - blockFont) - 1) < 0.01)
        #expect(abs(name.valueBox.label.font.pointSize - (pane.goeRow.valueBox.label.font.pointSize + 1)) < 0.01)
        #expect(name.frame.height > pane.goeRow.frame.height)
        #expect(abs(
            name.frame.height / pane.goeRow.frame.height - nameFont / blockFont
        ) < 0.01)
        // Wider than them, overhanging to the right.
        #expect(name.frame.maxX > pane.bounds.width)
        #expect(block.allSatisfy { $0.frame.minX == name.frame.minX })
        // Separated from them by the same hairline that separates two chips.
        let boxes = pane.elementRow.backgroundView.subviews
        let chipGap = boxes[1].frame.minX - boxes[0].frame.maxX
        #expect(abs((pane.elementNameRow.frame.minY - name.frame.maxY) - chipGap) < 0.5)
        // It is the only row with the rule between label and value.
        #expect(!name.divider.isHidden)
        #expect(block.allSatisfy { $0.divider.isHidden })
    }

    @Test func pane2026LabelsEachRowWithItsPartOfTheElement() {
        let pane = make2026Pane()

        #expect(pane.totalRow.labelText == "Jerry Hsu")
        #expect(pane.totalRow.valueText == "6.40")
        #expect(pane.elementNameRow.labelText == "3Lz")
        #expect(pane.baseValueRow.labelText == "BASE VALUE:")
        #expect(pane.baseValueRow.valueText == "5.90")
        #expect(pane.goeRow.labelText == "EXECUTION:")
        #expect(pane.goeRow.valueText == "0.50")
    }

    /// The values of the block sit in one column, so they line up down the pane.
    @Test func pane2026AlignsTheBlocksValuesInOneColumn() {
        let pane = make2026Pane()
        let baseValue = pane.baseValueRow.valueBox.frame
        let goe = pane.goeRow.valueBox.frame

        #expect(abs(baseValue.minX - goe.minX) < 0.5)
        #expect(abs(baseValue.width - goe.width) < 0.5)
        #expect(abs(goe.maxX - pane.bounds.width) < 0.5)
    }

    @Test func pane2026FillsTheGoeCellByTheSignOfTheValue() {
        #expect(make2026Pane().goeRow.valueCellColor == Color.isu2026Positive)
        #expect(make2026Pane(goeValue: "-1.19").goeRow.valueCellColor == Color.isu2026Negative)
    }

    /// The boxes are laid out from the modes the pane is handed, without waiting for a size change.
    @Test func pane2026LaysOutTheBoxesItIsGiven() {
        let pane = Isu2026TechnicalPaneView()
        pane.frame = CGRect(x: 0.0, y: 0.0, width: 330.0, height: 144.0)
        pane.update(from: TechnicalViewModel(
            skaterName: "ALI",
            elementName: "3Lz",
            baseValue: "5.90",
            goeValue: "0.50",
            totalValue: "6.40",
            boxModes: Array(repeating: ElementBoxView.Mode.unscored, count: 10),
            style: .isu2026
        ))
        pane.layoutIfNeeded()

        // No background behind the boxes in this style.
        #expect(pane.elementRow.backgroundView.backgroundColor == .clear)
        let boxes = pane.elementRow.backgroundView.subviews
        #expect(boxes.count == 10)
        #expect(boxes.allSatisfy { pane.elementRow.bounds.contains($0.frame) })
        #expect(boxes.allSatisfy { abs($0.frame.width - $0.frame.height) < 0.5 })
        // Evenly pitched from the row's left inset, and packed with only a hairline between them —
        // the separation is a fraction of a box, not a share of the row.
        let pitch = boxes[1].frame.minX - boxes[0].frame.minX
        for (left, right) in zip(boxes, boxes.dropFirst()) {
            let gap = right.frame.minX - left.frame.maxX
            #expect(abs((right.frame.minX - left.frame.minX) - pitch) < 0.5)
            #expect(gap < left.frame.width * 0.25)
        }
    }

    @Test func pane2026DropsOnlyTheBoxRowWithoutElementBoxes() {
        let shown = make2026Pane(showsElementBox: true)
        let hidden = make2026Pane(showsElementBox: false)

        #expect(!shown.elementRow.isHidden)
        #expect(hidden.elementRow.isHidden)
        #expect(hidden.elementRow.frame == .zero)
        // The text rows keep their place — the pane's unused space is below them.
        #expect(hidden.totalRow.frame == shown.totalRow.frame)
        #expect(hidden.goeRow.frame == shown.goeRow.frame)
        #expect(hidden.bounds == shown.bounds)
    }

    /// Each style's mode is its own cache key, so the overlay has to pick the pane the mode names.
    @Test func videoOverlayShowsThePaneItsStyleNames() {
        let viewModel = TechnicalViewModel(
            skaterName: "ALI",
            elementName: "3Lz",
            baseValue: "5.90",
            goeValue: "0.50",
            totalValue: "6.40",
            boxModes: [.positive]
        )

        let classic = VideoOverlay(mode: .technicalPane(viewModel))
        #expect(!classic.technicalPane.isHidden)
        #expect(classic.technicalPane2026.isHidden)

        let reordered = VideoOverlay(mode: .technicalPane(TechnicalViewModel(
            skaterName: viewModel.skaterName,
            elementName: viewModel.elementName,
            baseValue: viewModel.baseValue,
            goeValue: viewModel.goeValue,
            totalValue: viewModel.totalValue,
            boxModes: viewModel.boxModes,
            style: .classic2
        )))
        #expect(!reordered.technicalPaneClassic2.isHidden)
        #expect(reordered.technicalPane.isHidden)
        #expect(reordered.technicalPane2026.isHidden)

        let isu2026 = VideoOverlay(mode: .technicalPane(TechnicalViewModel(
            skaterName: viewModel.skaterName,
            elementName: viewModel.elementName,
            baseValue: viewModel.baseValue,
            goeValue: viewModel.goeValue,
            totalValue: viewModel.totalValue,
            boxModes: viewModel.boxModes,
            style: .isu2026
        )))
        #expect(isu2026.technicalPane.isHidden)
        #expect(isu2026.technicalPaneClassic2.isHidden)
        #expect(!isu2026.technicalPane2026.isHidden)
    }

    @Test func panesOfBothStylesShareTheOverlaysTopLeftCorner() {
        let overlay = VideoOverlay(mode: .none)
        overlay.bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        overlay.layoutIfNeeded()

        // Both panes hang off the same corner; the metrics are independent, so compare with a
        // tolerance rather than the exact floats.
        #expect(abs(overlay.technicalPane.frame.minX - overlay.technicalPane2026.frame.minX) < 0.5)
        #expect(abs(overlay.technicalPane.frame.minY - overlay.technicalPane2026.frame.minY) < 0.5)
        // The 2026 pane carries one more row, so it is the taller of the two.
        #expect(overlay.technicalPane2026.frame.height > overlay.technicalPane.frame.height)
    }
}
