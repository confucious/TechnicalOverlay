//
//  ElementNameExpanderTests.swift
//  ProtocolParserTests
//
//  The expansion rules, the frozen worked examples and the whole-fixture sweeps for singles, pairs
//  and ice dance (`docs/architecture/abbreviation-expansion.md` §4, §5, §9).
//

import Foundation
import Testing
@testable import ProtocolParser

@Suite("Element name expansion")
struct ElementNameExpanderTests {

    private let expander = ElementNameExpander()

    private func expanded(_ abbreviation: String) -> String {
        expander.displayName(for: abbreviation)
    }

    // MARK: - Jumps

    @Test("a jump carries its revolution count and its name")
    func jumpsAndNumbers() {
        #expect(expanded("3S") == "3 Salchow")
        #expect(expanded("2Lz") == "2 Lutz")
        #expect(expanded("1A") == "1 Axel")
        #expect(expanded("4T") == "4 Toeloop")
        #expect(expanded("1F") == "1 Flip")
        #expect(expanded("2Lo") == "2 Loop")
    }

    @Test("Euler is never numbered")
    func euler() {
        #expect(expanded("Eu") == "Euler")
        #expect(expanded("2A+Eu+2F") == "2 Axel + Euler + 2 Flip")
    }

    @Test("a jump the protocol printed without a revolution count keeps it that way")
    func numberlessJumps() {
        #expect(expanded("A") == "Axel")
        #expect(expanded("T") == "Toeloop")
        #expect(expanded("A*") == "Axel (Invalid)")
        #expect(expanded("Lo*") == "Loop (Invalid)")
    }

    @Test("the parts of a combination are joined with a spaced plus")
    func separator() {
        #expect(expanded("3Tb1+2T") == "3 Toeloop + 2 Toeloop")
        #expect(expanded("3S+1A+2T+SEQ") == "3 Salchow + 1 Axel + 2 Toeloop + SEQ")
    }

    // MARK: - Markers

    @Test("the bonus marker is ignored wherever it sits")
    func bonusMarker() {
        #expect(expanded("3Tb1") == "3 Toeloop")
        #expect(expanded("3Tb1+2T") == "3 Toeloop + 2 Toeloop")
        #expect(expanded("3Lz<b1") == "3 Lutz")           // bonus after the marker
        #expect(expanded("3S<b1") == "3 Salchow")
        // A pairs twist and a pair throw carry the same bonus.
        #expect(expanded("3Tw3b1") == "3 Twist Lift 3")
        #expect(expanded("3SThb1") == "Throw 3 Salchow")
    }

    /// The FS Manager PDF prints the marker without its amount — the value is only in the Bonus
    /// column — so a trailing bare `b` is a bonus marker too, and a trailing `B` is still a level.
    @Test("an amount-less bonus marker is ignored as well")
    func amountlessBonusMarker() {
        #expect(expanded("3Tb") == "3 Toeloop")
        #expect(expanded("2Ab") == "2 Axel")
        #expect(expanded("3Sb") == "3 Salchow")
        #expect(expanded("3Lzb") == "3 Lutz")
        #expect(expanded("3Tb+2T") == "3 Toeloop + 2 Toeloop")
        #expect(expanded("3Fb+2T<<*") == "3 Flip + 2 Toeloop (Invalid)")

        // A trailing `B` is a level, not a marker: untouched, in every vocabulary that uses one.
        #expect(expanded("CCoSpBV") == "Change Combo Spin B V")
        #expect(expanded("StSqB") == "Step Sequence B")
        #expect(expanded("1LiB") == "1 Lift B")
        #expect(expanded("1TwB") == "1 Twist Lift B")
    }

    @Test("under-rotation, downgrade and edge markers are ignored")
    func markers() {
        #expect(expanded("2A<") == "2 Axel")
        #expect(expanded("3Lo<<") == "3 Loop")
        #expect(expanded("2Lz!") == "2 Lutz")
        #expect(expanded("2Lze") == "2 Lutz")
        #expect(expanded("3Lzq") == "3 Lutz")
        #expect(expanded("2Lz!<") == "2 Lutz")
        #expect(expanded("2Lo+2Tq") == "2 Loop + 2 Toeloop")
    }

    @Test("an asterisk marks the token it belongs to invalid")
    func invalidFlag() {
        #expect(expanded("1Lz*") == "1 Lutz (Invalid)")
        #expect(expanded("1Lz*+COMBO") == "1 Lutz (Invalid) + COMBO")
        #expect(expanded("3Sb1+COMBO+1T*") == "3 Salchow + COMBO + 1 Toeloop (Invalid)")
        #expect(expanded("A*") == "Axel (Invalid)")
        // Both tokens flagged, each on its own part.
        #expect(expanded("2Lz+SEQ+1A*+2Lo*") == "2 Lutz + SEQ + 1 Axel (Invalid) + 2 Loop (Invalid)")
        // The flag works on a dance element too.
        #expect(expanded("RoLi4*") == "Rotational Lift 4 (Invalid)")
    }

    // MARK: - Call tokens

    @Test("the call tokens are shown as published")
    func callTokens() {
        #expect(expanded("2Lz+COMBO") == "2 Lutz + COMBO")
        #expect(expanded("3Lo+REP") == "3 Loop + REP")
        #expect(expanded("2Fq+REP") == "2 Flip + REP")
        #expect(expanded("T+COMBO+2T*+REP") == "Toeloop + COMBO + 2 Toeloop (Invalid) + REP")
        #expect(expanded("SEQ") == "SEQ")
        #expect(expanded("COMBO") == "COMBO")
        #expect(expanded("REP") == "REP")
        // The dance extra-element token is a call token, not an element.
        #expect(expanded("RoLi4+ExEI") == "Rotational Lift 4 + ExEI")
        // A call token keeps its place rather than moving to the end.
        #expect(expanded("2Lz+SEQ+1A+2Lo") == "2 Lutz + SEQ + 1 Axel + 2 Loop")
    }

    // MARK: - Step sequences and choreographic elements

    @Test("a step sequence is expanded with its level")
    func stepSequences() {
        #expect(expanded("StSqB+kpNNNN") == "Step Sequence B")
        #expect(expanded("StSq1+kpYNNN") == "Step Sequence 1")
        #expect(expanded("StSq2+kpYYNN") == "Step Sequence 2")
        #expect(expanded("StSq3+kpYNYY") == "Step Sequence 3")
        #expect(expanded("StSq4+kpYYYY") == "Step Sequence 4")
        #expect(expanded("StSq4b0.5+kpYYYY") == "Step Sequence 4")   // bonus ignored, no dangling +
    }

    @Test("the choreographic codes keep their digit; only a p prefix is dropped")
    func choreographic() {
        #expect(expanded("ChSq1") == "Choreo Sequence 1")
        #expect(expanded("ChSp1") == "Choreo Spin 1")
        #expect(expanded("pChSq1") == "Choreo Sequence 1")
        // The dance and pairs members of the family, each a different name.
        #expect(expanded("ChSt1") == "Choreo Char Step Sequence 1")
        #expect(expanded("pChSt1") == "Choreo Step Sequence 1")
        #expect(expanded("ChSl1") == "Choreo Slide 1")
        #expect(expanded("ChLi1") == "Choreo Lift 1")
        #expect(expanded("ChAJ1") == "Choreo Assisted Jumps 1")
        #expect(expanded("ChPSp1") == "Choreo Pair Spin 1")
        #expect(expanded("ChPLi1") == "Choreo Pair Lift 1")
        #expect(expanded("CDE4") == "Creative Dance Element 4")
        #expect(expanded("CDEB") == "Creative Dance Element B")
    }

    // MARK: - Spins

    @Test("a spin is expanded with its level and its reduced-value flag")
    func spins() {
        #expect(expanded("CCoSp4") == "Change Combo Spin 4")
        // The reduced-value V is separated from the level by a space.
        #expect(expanded("CCoSp1V") == "Change Combo Spin 1 V")
        #expect(expanded("CCoSp2V") == "Change Combo Spin 2 V")
        #expect(expanded("CCoSpBV") == "Change Combo Spin B V")
        #expect(expanded("FCCoSp4") == "Flying Change Combo Spin 4")
        #expect(expanded("CSp2") == "Camel Spin 2")
        #expect(expanded("SSpB") == "Sit Spin B")
        #expect(expanded("FCSp3") == "Flying Camel Spin 3")
        #expect(expanded("CSSp4") == "Change Sit Spin 4")
        #expect(expanded("USp2") == "Upright Spin 2")
        #expect(expanded("FUSpB") == "Flying Upright Spin B")
    }

    @Test("a spin the panel called with no level gets the name alone")
    func spinsWithoutLevel() {
        #expect(expanded("CoSp") == "Combo Spin")
        #expect(expanded("CCSp") == "Change Camel Spin")
        #expect(expanded("FSSp") == "Flying Sit Spin")
        #expect(expanded("CCoSp") == "Change Combo Spin")
        #expect(expanded("CSSp") == "Change Sit Spin")
        #expect(expanded("CoSpV") == "Combo Spin V")      // a V with no level still shows
    }

    @Test("the longest spin code wins, and a spin is not a jump")
    func longestSpinCode() {
        #expect(expanded("CCSp3") == "Change Camel Spin 3")
        #expect(expanded("FSSp3") == "Flying Sit Spin 3")
        #expect(expanded("SSp2") == "Sit Spin 2")
        #expect(expanded("FCSSp4") == "Flying Change Sit Spin 4")
        // The pairs and dance spins are spins by the same rules, and `PCoSp` beats `PSp`.
        #expect(expanded("PSpB") == "Pair Spin B")
        #expect(expanded("PCoSp3") == "Pair Combo Spin 3")
        #expect(expanded("DSp2") == "Dance Spin 2")
    }

    // MARK: - Pairs

    @Test("a throw puts the word first and keeps the jump's number and name")
    func pairsThrows() {
        #expect(expanded("3STh") == "Throw 3 Salchow")
        #expect(expanded("2LoTh") == "Throw 2 Loop")
        #expect(expanded("1LoTh") == "Throw 1 Loop")
        #expect(expanded("2LzTh") == "Throw 2 Lutz")
        #expect(expanded("4STh") == "Throw 4 Salchow")
    }

    @Test("a twist lift keeps both numbers apart")
    func pairsTwists() {
        #expect(expanded("3Tw3") == "3 Twist Lift 3")
        #expect(expanded("2Tw4") == "2 Twist Lift 4")
        #expect(expanded("1TwB") == "1 Twist Lift B")
    }

    @Test("a pair lift is the group number, the word, the level")
    func pairsLifts() {
        #expect(expanded("1Li4") == "1 Lift 4")
        #expect(expanded("4LiB") == "4 Lift B")
        #expect(expanded("1Li3") == "1 Lift 3")
        #expect(expanded("2LiB") == "2 Lift B")
        #expect(expanded("5ALi4") == "5 Axel Lasso Lift 4")
        #expect(expanded("5TLi3") == "5 Toe Lasso Lift 3")
        // `4Li3` is a group 4 lift at level 3, not a level-3 reading of something else.
        #expect(expanded("4Li3") == "4 Lift 3")
    }

    @Test("death spirals and pivot figures carry a direction and a level")
    func pairsSpiralsAndPivot() {
        #expect(expanded("BoDs3") == "Backward Outside Death Spiral 3")
        #expect(expanded("FiDsB") == "Forward Inside Death Spiral B")
        #expect(expanded("FoDs2") == "Forward Outside Death Spiral 2")
        #expect(expanded("BiDs1") == "Backward Inside Death Spiral 1")
        #expect(expanded("PiF1") == "Pivot Figure 1")
    }

    @Test("the pairs solo vocabulary keeps the singles rules")
    func pairsSoloVocabulary() {
        #expect(expanded("3Tb1+2A+SEQ") == "3 Toeloop + 2 Axel + SEQ")
        #expect(expanded("2F<") == "2 Flip")
        #expect(expanded("ChSq1") == "Choreo Sequence 1")
        #expect(expanded("2A+1A+SEQ") == "2 Axel + 1 Axel + SEQ")
    }

    // MARK: - Ice dance

    @Test("a dance lift is the kind, the word, the level")
    func danceLifts() {
        #expect(expanded("StaLi4") == "Stationary Lift 4")
        #expect(expanded("SlLi3") == "Straight Line Lift 3")
        #expect(expanded("CuLi4") == "Curve Lift 4")
        #expect(expanded("RoLi2") == "Rotational Lift 2")
        // The ISU list spells the straight-line lift `SiLi`; the pages write `SlLi`.
        #expect(expanded("SiLi4") == "Straight Line Lift 4")
    }

    @Test("a two-partner element is one name, with each level on its own letter")
    func recombinedHalves() {
        #expect(expanded("SqTwW4+SqTwM4") == "Sequential Twizzles W 4 / M 4")
        #expect(expanded("SyTwW3+SyTwM4") == "Synchronized Twizzles W 3 / M 4")
        #expect(expanded("pSTwW4+pSTwM1") == "Synchronized Twizzles W 4 / M 1")
        #expect(expanded("MiStW1+MiStM2") == "Midline Steps W 1 / M 2")
        #expect(expanded("CiStW2+CiStM2") == "Circular Steps W 2 / M 2")
        #expect(expanded("DiStW1+DiStM1") == "Diagonal Steps W 1 / M 1")
        #expect(expanded("SeStW1+SeStM1") == "Serpentine Steps W 1 / M 1")
        #expect(expanded("OFTW2+OFTM3") == "One Foot Turns W 2 / M 3")
        // A half the panel did not level keeps its letter and no number.
        #expect(expanded("SqTwW2+SqTwM") == "Sequential Twizzles W 2 / M")
        #expect(expanded("MiStW1+MiStMB") == "Midline Steps W 1 / M B")
    }

    @Test("a half with no partner half keeps the singular form")
    func singleHalves() {
        #expect(expanded("SqTwW4") == "Sequential Twizzle W 4")
        #expect(expanded("SyTwM3") == "Synchronized Twizzle M 3")
        #expect(expanded("MiStW2") == "Midline Step W 2")
        #expect(expanded("OFTM1") == "One Foot Turn M 1")
    }

    @Test("recombination is narrow: same code, one W and one M")
    func recombinationIsNarrow() {
        // Two different lifts are two names, joined.
        #expect(expanded("StaLi4+RoLi4") == "Stationary Lift 4 + Rotational Lift 4")
        #expect(expanded("SlLi3+RoLi3") == "Straight Line Lift 3 + Rotational Lift 3")
        // Two different step sequences are not one element either.
        #expect(expanded("MiStW1+DiStM2") == "Midline Step W 1 + Diagonal Step M 2")
        // The same partner letter twice is not a pair.
        #expect(expanded("SqTwW4+SqTwW4") == "Sequential Twizzle W 4 + Sequential Twizzle W 4")
    }

    @Test("the dance-only markers are stripped inside the dance rules")
    func danceMarkers() {
        #expect(expanded("SqTwW4S+SqTwM4S") == "Sequential Twizzles W 4 / M 4")   // separation
        #expect(expanded("MiStW1S+MiStM1S") == "Midline Steps W 1 / M 1")
        #expect(expanded("StaLi4>") == "Stationary Lift 4")                      // extended lift
        #expect(expanded("OFTW1S") == "One Foot Turn W 1")
    }

    @Test("the marker collisions stay resolved")
    func markerCollisions() {
        #expect(expanded("3S") == "3 Salchow")            // S is the marker and the jump code
        #expect(expanded("S") == "Salchow")
        #expect(expanded("StSq2") == "Step Sequence 2")   // q is a marker and a letter of StSq
        #expect(expanded("ChSq1") == "Choreo Sequence 1")
        #expect(expanded("ChSp1e") == "Choreo Spin 1")    // e is a marker on a choreographic code
        // And a code that ends in `e` is not eaten by the marker strip.
        #expect(expanded("SpEe") == "Spiral Edge Element")
        #expect(expanded("CrEe") == "Crouch Edge Element")
    }

    @Test("the pattern-dance elements follow their own two grammars")
    func patternDances() {
        #expect(expanded("FO1Sq4+kpYYYY") == "Fourteenstep Seq 1 4")
        #expect(expanded("TA2Sq1+kpNYNN") == "Tango Seq 2 1")
        #expect(expanded("TA1SqB+kpNNNN") == "Tango Seq 1 B")
        // The slot form: the first number is the element's place, the last the level.
        #expect(expanded("1GW2+kpYNNY") == "Golden Waltz 1 2")
        #expect(expanded("1WW1+kpNNNY") == "Pattern Dance 1 1")
        #expect(expanded("2WWB+kpNNNN") == "Pattern Dance 2 B")
        // The generic code carries no dance identity: RPD's digit is a sequence count.
        #expect(expanded("RPD41Sq4+kpYYYY") == "Pattern Dance Seq 1 4")
        #expect(expanded("RPD22Sq1+kpNYNN") == "Pattern Dance Seq 2 1")
    }

    @Test("the ISU codes with no page in the set still classify")
    func unmeasuredCodes() {
        #expect(expanded("PSt4") == "Pattern Dance Type Step Sequence Style D 4")
        #expect(expanded("SoTw3") == "Solo Twizzles 3")
        #expect(expanded("SpEe2") == "Spiral Edge Element 2")
        #expect(expanded("CrEe1") == "Crouch Edge Element 1")
        #expect(expanded("SeEs2") == "Spread Eagle Edge Element 2")
        #expect(expanded("IBEe1") == "Ina Bauer Type Edge Element 1")
    }

    @Test("a translator that implements nothing returns the abbreviation unchanged")
    func identityDefault() {
        struct Untranslated: ElementNameTranslating {}
        let translator: ElementNameTranslating = Untranslated()
        #expect(translator.displayName(for: "3Tb1+2T") == "3Tb1+2T")
        #expect(translator.displayName(for: "StSq4b0.5+kpYYYY") == "StSq4b0.5+kpYYYY")
    }

    // MARK: - Fixture sweeps

    @Test("every row of the five singles fixtures is classified, with nothing passed through")
    func singlesSweep() throws {
        try sweep(
            pages: Fixture.singlesDetailPages,
            expectedRows: 535,
            expectedAbbreviations: 187,
            callTokens: ["SEQ", "COMBO", "REP", "ExEI"],
            recombines: false
        )
    }

    @Test("every row of the five pairs fixtures is classified, with nothing passed through")
    func pairsSweep() throws {
        try sweep(
            pages: Fixture.pairsDetailPages,
            expectedRows: 182,
            expectedAbbreviations: 66,
            callTokens: ["SEQ", "COMBO", "REP", "ExEI"],
            recombines: false
        )
    }

    @Test("every row of the thirteen ice-dance fixtures is classified, with nothing passed through")
    func danceSweep() throws {
        try sweep(
            pages: Fixture.danceDetailPages,
            expectedRows: 247,
            expectedAbbreviations: 121,
            callTokens: ["SEQ", "COMBO", "REP", "ExEI"],
            recombines: true
        )
    }

    @Test("no row on any committed page expands to something malformed")
    func everyPageStaysWellFormed() throws {
        var rows = 0
        for page in Fixture.detailPages + Fixture.danceDetailPages {
            let segment = try ProtocolHTMLParser.parseSegment(html: try Fixture.html(page))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    let name = expanded(element.abbreviation)
                    #expect(!name.isEmpty, "\(page) #\(element.index) \(element.abbreviation)")
                    #expect(!name.hasPrefix(" + ") && !name.hasSuffix(" + "))
                    #expect(!name.contains("+ +"))
                    #expect(!name.contains("  "), "\(page) \(element.abbreviation) → \(name)")
                    #expect(!name.lowercased().contains("kp"))
                }
            }
        }
        #expect(rows == 825 + 247, "the committed pages hold 825 static and 247 dance element rows")
    }

    /// The whole-page check: every abbreviation is classified, no token comes back verbatim, and no
    /// row is left malformed (`abbreviation-expansion.md` §4.9, §9).
    private func sweep(
        pages: [String],
        expectedRows: Int,
        expectedAbbreviations: Int,
        callTokens: Set<String>,
        recombines: Bool
    ) throws {
        var rows = 0
        var abbreviations: Set<String> = []

        for page in pages {
            let segment = try ProtocolHTMLParser.parseSegment(html: try Fixture.html(page))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    abbreviations.insert(element.abbreviation)
                    assertClassified(
                        element.abbreviation,
                        context: "\(page) #\(element.index)",
                        callTokens: callTokens,
                        recombines: recombines)
                }
            }
        }

        #expect(rows == expectedRows, "\(pages.count) pages hold \(expectedRows) element rows")
        #expect(abbreviations.count == expectedAbbreviations,
                "expected \(expectedAbbreviations) distinct abbreviations, got \(abbreviations.count)")
    }

    /// One row: every token classified, nothing coming back verbatim, and no part left malformed
    /// (`abbreviation-expansion.md` §4.9, §9).
    ///
    /// The surviving parts must line up one-for-one with the tokens that are not dropped — except
    /// that a recombined two-partner element is two tokens and one part. Call tokens are the other
    /// exception: their expansion *is* themselves.
    private func assertClassified(
        _ abbreviation: String,
        context: String,
        callTokens: Set<String>,
        recombines: Bool
    ) {
        let name = expanded(abbreviation)
        let parts = name.components(separatedBy: " + ")
        let survivors = abbreviation
            .components(separatedBy: "+")
            .filter { !$0.hasPrefix("kp") }
        let recombined = recombines && parts.count == survivors.count - 1

        #expect(parts.count == survivors.count || recombined, "\(context) \(abbreviation) → \(parts)")
        for part in parts where !callTokens.contains(part) {
            #expect(!survivors.contains(part),
                    "verbatim passthrough: \(context) \(abbreviation) → \(part)")
        }
        #expect(!name.isEmpty, Comment(rawValue: context))
        #expect(!name.hasPrefix(" + ") && !name.hasSuffix(" + "), Comment(rawValue: context))
        #expect(!name.contains("+ +"), Comment(rawValue: context))
        #expect(!name.contains("  "), "\(context) \(abbreviation) → \(name)")
        #expect(!name.lowercased().contains("kp"), Comment(rawValue: context))
    }

    /// The PDFs print the bonus marker without its amount (`3Tb`, `2Ab`, `3Lzb`), so they are the
    /// fixtures that catch a marker rule that only knows `b1` (`abbreviation-expansion.md` §4.6).
    @Test("every row of the two protocol PDFs is classified, with nothing passed through")
    func pdfSweep() throws {
        var rows = 0
        var abbreviations: Set<String> = []

        for name in Fixture.protocolPDFs {
            let segment = try ProtocolPDFParser.parseSegment(data: try Fixture.pdf(name))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    abbreviations.insert(element.abbreviation)
                    assertClassified(
                        element.abbreviation,
                        context: "\(name) \(skater.name) #\(element.index)",
                        callTokens: ["SEQ", "COMBO", "REP", "ExEI"],
                        recombines: false)
                }
            }
        }

        #expect(rows == 84 + 48, "the two PDFs hold \(rows) element rows")
        #expect(abbreviations.count == 46, "expected 46 distinct PDF abbreviations, got \(abbreviations.count)")
        // The marker forms that only these documents print.
        #expect(abbreviations.isSuperset(of: ["2Ab", "3Sb", "3Lzb", "3Tb+2T", "3Fb+2T<<*"]))
    }
}
