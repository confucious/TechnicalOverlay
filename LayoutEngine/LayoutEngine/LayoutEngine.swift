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
}

enum CornerDirection {
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
    
    func fontSize() -> CGFloat {
        return bounds.size.height * 0.75
    }
}
