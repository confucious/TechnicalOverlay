//
//  TechnicalOverlayTests.swift
//  TechnicalOverlayTests
//
//  Created by Jerry Hsu on 9/21/25.
//

import Testing
@testable import Technical_Overlay

struct TechnicalOverlayTests {

    @Test func example() {
        [
            ("0.", 0),
            ("0.07", 7),
            ("0.7", 70),
            ("0.70", 70),
            ("-1.", -100),
            ("-.", 0),
            ("7", 700),
            ("-1.-1", -110),
            ("1.-12", 112),
        ].forEach { (string, value) in
            #expect(string.toHundredthsInt() == value)
        }
    }
    
    @Test func specific() {
        #expect("-1.-1".toHundredthsInt() == -110)
    }

}
