//
//  IsuTechnicalPaneView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 9/28/25.
//

import UIKit

public struct TechnicalViewModel: Hashable {
    public init(skaterName: String, elementName: String, baseValue: String, goeValue: String, totalValue: String, boxModes: [ElementBoxView.Mode]) {
        self.skaterName = skaterName
        self.elementName = elementName
        self.baseValue = baseValue
        self.goeValue = goeValue
        self.totalValue = totalValue
        self.boxModes = boxModes
    }
    
    public var skaterName: String
    public var elementName: String
    public var baseValue: String
    public var goeValue: String
    public var totalValue: String
    public var boxModes: [ElementBoxView.Mode]
}

public class IsuTechnicalPaneView: UIView {

    let elementRow = ElementRowView()
    let elementNameView = ElementNameView()
    let elementScore = ElementScoreView()
    let total = ProgramTotalView()
    
    public init() {
        super.init(frame: CGRect(
            origin: .zero,
            size: CGSize(width: 100.0, height: 200.0)
        ))
        addSubview(elementRow)
        addSubview(elementNameView)
        addSubview(elementScore)
        addSubview(total)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(from viewModel: TechnicalViewModel) {
        total.skaterName = viewModel.skaterName
        total.totalValue = viewModel.totalValue
        elementNameView.name = viewModel.elementName
        elementScore.baseValue = viewModel.baseValue
        elementScore.goeValue = viewModel.goeValue
        elementRow.boxModes = viewModel.boxModes
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.size.width
        let mainRowHeight = bounds.size.height * Metrics.mainRowPercent
        let borderSize = mainRowHeight * Metrics.borderPercent
        let boxRowRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: width,
                height: mainRowHeight * Metrics.boxRowPercent + borderSize
            )
        )
        let mainRowRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: width,
                height: mainRowHeight + borderSize * 2
            )
        )
        elementRow.frame = boxRowRect
        elementNameView.frame = mainRowRect
            .offsetBy(dx: 0.0, dy: boxRowRect.maxY)
        elementScore.frame = elementNameView.frame
            .offsetBy(dx: 0.0, dy: mainRowHeight + borderSize)
        total.frame = elementScore.frame.offsetBy(dx: 0.0, dy: mainRowHeight + borderSize)
        
        elementRow.backgroundView.cornerConfiguration = elementNameView
            .roundedCornerConfiguration(corners: [.nw, .ne])
        elementNameView.cornerConfiguration = elementNameView
            .roundedCornerConfiguration(corners: [.ne])
        total.cornerConfiguration = total.roundedCornerConfiguration(corners: [.sw, .se])
    }
}
