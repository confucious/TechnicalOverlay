//
//  IsuLowerThirdView.swift
//  LayoutEngine
//
//  Created by Jerry Hsu on 9/28/25.
//


import UIKit

public class IsuLowerThirdView: UIView {

    let upperLine: UpperLineView
    let lowerLine: LowerLineView

    init() {
        upperLine = UpperLineView()
        lowerLine = LowerLineView()
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public class UpperLineView: UIView {
        let nameLabel = UILabel()

        init() {
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    public class LowerLineView: UIView {
        let centerLabel = UILabel()
        let leftLabel = UILabel()
        let rightLabel = UILabel()
        
        init() {
            super.init(frame: .zero)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
