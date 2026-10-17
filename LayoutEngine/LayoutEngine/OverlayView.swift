//
//  OverlayView.swift
//  LayoutEngine
//
//  The base every overlay row is built on.
//

import UIKit

/// Base for the overlay's views, which are built in code only.
///
/// Marking the storyboard initializer unavailable here means every subclass inherits that instead of
/// repeating a `fatalError` stub.
public class OverlayView: UIView {

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
