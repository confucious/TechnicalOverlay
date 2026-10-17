//
//  IsuTechnicalPaneView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 9/28/25.
//

import UIKit

public struct TechnicalViewModel: Hashable {
    public init(
        skaterName: String,
        elementName: String,
        baseValue: String,
        goeValue: String,
        totalValue: String,
        boxModes: [ElementBoxView.Mode],
        showsElementBox: Bool = true
    ) {
        self.skaterName = skaterName
        self.elementName = elementName
        self.baseValue = baseValue
        self.goeValue = goeValue
        self.totalValue = totalValue
        self.boxModes = boxModes
        self.showsElementBox = showsElementBox
    }
    
    public var skaterName: String
    public var elementName: String
    public var baseValue: String
    public var goeValue: String
    public var totalValue: String
    public var boxModes: [ElementBoxView.Mode]
    /// Whether the element box row is drawn above the element name. Part of the view model because
    /// it changes the rendered image, so it has to differ in `VideoOverlay.Mode` equality.
    public var showsElementBox: Bool
}

public class IsuTechnicalPaneView: UIView {

    let elementRow = ElementRowView()
    let elementNameView = ElementNameView()
    let elementScore = ElementScoreView()
    let total = ProgramTotalView()

    /// Whether the element box row is drawn. Hiding it removes the row's height from the stack, so
    /// the name, score and total rows sit higher on screen at their usual size.
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
        addSubview(elementRow)
        addSubview(elementNameView)
        addSubview(elementScore)
        addSubview(total)
        elementRow.isHidden = !showsElementBox
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
        showsElementBox = viewModel.showsElementBox
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
        elementRow.frame = showsElementBox ? boxRowRect : .zero
        // Without the box row the three scored rows stack from the top of the pane — the pane keeps
        // its frame and aspect, so only the rows move up.
        let rowsTop = showsElementBox ? boxRowRect.maxY : 0.0
        elementNameView.frame = mainRowRect
            .offsetBy(dx: 0.0, dy: rowsTop)
        elementScore.frame = elementNameView.frame
            .offsetBy(dx: 0.0, dy: mainRowHeight + borderSize)
        total.frame = elementScore.frame.offsetBy(dx: 0.0, dy: mainRowHeight + borderSize)
        
        elementRow.backgroundView.cornerConfiguration = elementNameView
            .roundedCornerConfiguration(corners: [.nw, .ne])
        elementNameView.cornerConfiguration = elementNameView
            .roundedCornerConfiguration(corners: showsElementBox ? [.ne] : [.nw, .ne])
        total.cornerConfiguration = total.roundedCornerConfiguration(corners: [.sw, .se])
    }
}
