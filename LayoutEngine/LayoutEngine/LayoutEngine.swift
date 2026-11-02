//
//  LayoutEngine.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 9/21/25.
//

import UIKit

enum Color {
    static let nameBox = UIColor(red: 83.0/255, green: 144.0/255, blue: 205.0/255, alpha: 1.0)
    static let positive = UIColor(red: 79.0/255, green: 153.0/255, blue: 47.0/255, alpha: 1.0)
    static let negative = UIColor(red: 195.0/255, green: 84.0/255, blue: 65.0/255, alpha: 1.0)
    static let technicalBackground = UIColor.lightGray
    static let totalScore = UIColor(red: 195/255.0, green: 102/255.0, blue: 147/255.0, alpha: 1.0)
    static let bottomLine = UIColor.darkGray

    // ISU 2026 pane: black text on white and light-gray rows, with saturated score cells.

    /// A row that carries text only.
    static let isu2026Row = UIColor.white
    /// The name row takes the broadcast leader row's look: blue behind white text, with the running
    /// total in its own band.
    static let isu2026NameRow = UIColor(red: 0.0/255, green: 80.0/255, blue: 178.0/255, alpha: 1.0)
    static let isu2026NameRowText = UIColor.white
    /// The rule between the name row's name and its running total.
    static let isu2026NameRowDivider = UIColor(white: 1.0, alpha: 0.25)
    /// The element-name row, which sits a shade darker than the rows around it.
    static let isu2026ElementRow = UIColor(white: 0.87, alpha: 1.0)
    static let isu2026Text = UIColor.black
    static let isu2026Positive = UIColor(red: 47.0/255, green: 166.0/255, blue: 0.0/255, alpha: 1.0)
    static let isu2026Negative = UIColor(red: 213.0/255, green: 11.0/255, blue: 14.0/255, alpha: 1.0)
    static let isu2026Neutral = UIColor(white: 0.62, alpha: 1.0)
    /// An unscored box is white, so it reads as an empty slot rather than a mark.
    static let isu2026Unscored = UIColor.white
    /// The box row has no background of its own, so the outline is what gives an empty slot its edge
    /// against a light frame — the one case a white fill cannot.
    static let isu2026BoxOutline = UIColor(white: 0.4, alpha: 1.0)
}

enum Metrics {
    static let boxRowPercent = CGFloat(0.6)
    static let boxBorderPercent = CGFloat(
        borderPercent / (boxRowPercent + borderPercent)
    )
    static let borderPercent = CGFloat(0.1)
    static let mainRowPercent = CGFloat(
        1/(3 + boxRowPercent + 5 * borderPercent)
    )
    static let cornerRadiusPercent = CGFloat(0.1)
    
    static let techPaneHeightPercent = CGFloat(0.16)
    static let techPaneAspectRatio = CGFloat(2.65)
    static let overlayBorderPercent = CGFloat(0.05)

    // The ISU 2026 pane: four text rows above a box row, all flush, so its rows share the pane's
    // height exactly and the pane is taller than the classic one to keep the text the same size.

    static let isu2026TechPaneHeightPercent = CGFloat(0.20)
    static let isu2026TechPaneAspectRatio = CGFloat(2.3)
    /// The name row's text is this many points larger than the rows below it, and the row is taller by
    /// exactly what that text needs — see `isu2026NameRowExtraHeight`.
    static let isu2026NameRowFontSizeIncrease = CGFloat(1)
    /// A row's text size, as a fraction of its height: `LabelBoxView` insets the label by 0.3 border
    /// top and bottom and sizes the font at 0.75 of the label's height.
    static let isu2026FontPercent = CGFloat(0.75) * (1 - 2 * 0.3 * borderPercent)
    /// How much taller a text row has to be to carry `isu2026NameRowFontSizeIncrease` more points —
    /// which is what keeps the name row's height proportional to its text.
    static let isu2026NameRowExtraHeight = isu2026NameRowFontSizeIncrease / isu2026FontPercent
    /// A chip's width, as a fraction of one of the text rows: the box row is `isu2026BoxRowPercent` of
    /// a text row, and a chip fills it less the top and bottom inset.
    static let isu2026ChipPercent = isu2026BoxRowPercent * (1 - 2 * isu2026BoxInsetPercent)
    /// The clear gap under the name row, relative to one of the text rows: the same hairline that
    /// separates two chips.
    static let isu2026NameRowGapPercent = isu2026ChipPercent * isu2026BoxGapPercent
    /// The name row overhangs the pane's other rows by this share of the pane's width.
    static let isu2026NameRowWidthPercent = CGFloat(1.15)
    /// The box row, relative to one of the pane's three text rows.
    static let isu2026BoxRowPercent = CGFloat(0.85)
    /// One of the three text rows below the name row, as a fraction of the pane less the name row's
    /// extra height.
    static let isu2026MainRowPercent = CGFloat(1)
        / (1 + isu2026NameRowGapPercent + 3 + isu2026BoxRowPercent)
    /// The box row's inset from its row's top and bottom, as a fraction of the row's height.
    static let isu2026BoxInsetPercent = CGFloat(0.15)
    /// The gap between two boxes, as a fraction of a box's width: a hairline, not a space.
    static let isu2026BoxGapPercent = CGFloat(0.1)
    
    static let lowerThirdHeightPercent = CGFloat(0.15)
    static let lowerThirdAspectRatio = CGFloat(8.5)

    /// The border width for a box `height` tall — every inset in the pane and lower-third rows is a
    /// multiple of it.
    static func borderInset(for height: CGFloat) -> CGFloat {
        height * borderPercent
    }

    /// The font size for a label `height` tall.
    static func fontSize(for height: CGFloat) -> CGFloat {
        height * 0.75
    }
}

nonisolated enum CornerDirection {
    case nw, ne, sw, se
}

extension UIView {
    func cornerRadius() -> UICornerRadius {
        return UICornerRadius(
            floatLiteral: bounds.size.height * Metrics.cornerRadiusPercent
        )
    }
    
    func roundedCornerConfiguration(corners: Set<CornerDirection> = [.nw, .ne, .sw, .se]) -> UICornerConfiguration {
        let radius = cornerRadius()
        return .corners(
            topLeftRadius: corners.contains(.nw) ? radius : nil,
            topRightRadius: corners.contains(.ne) ? radius: nil,
            bottomLeftRadius: corners.contains(.sw) ? radius : nil,
            bottomRightRadius: corners.contains(.se) ? radius : nil
        )
    }
}
