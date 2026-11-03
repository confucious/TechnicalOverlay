//
//  ProtocolPDFParserTests.swift
//  ProtocolParserTests
//
//  The ISU FS Manager PDF path (`docs/architecture/protocol-parser.md` §2.3, §4.8–§4.9).
//  The fixtures are the two published protocols of §3.2, committed beside these tests.
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ProtocolParser

@Suite("Protocol PDF")
struct ProtocolPDFParserTests {

    private let women = "ISU-FSKWSINGLES-QUAL000100.pdf"
    private let advancedNoviceMen = "ISU-FSKMSINGLES-ADVNOV-QUAL000100.pdf"

    // MARK: - Recognition

    @Test("a protocol document is recognised by its header, not its address")
    func recognisesPDF() throws {
        for name in Fixture.protocolPDFs {
            #expect(ProtocolPDFParser.isPDF(try Fixture.pdf(name)))
        }
        #expect(!ProtocolPDFParser.isPDF(Data(try Fixture.html("SEGM034.html").utf8)))
        #expect(!ProtocolPDFParser.isPDF(Data()))
    }

    @Test("bytes that are not a PDF are reported as unreadable")
    func nonPDFIsUnreadable() throws {
        #expect(throws: ProtocolParserError.unreadablePDF) {
            _ = try ProtocolPDFParser.parseSegment(data: Data("<html>not a pdf</html>".utf8))
        }
        #expect(throws: ProtocolParserError.unreadablePDF) {
            _ = try ProtocolPDFParser.parseSegment(data: Data())
        }
    }

    @Test("a PDF that is not a judges-details protocol is not recognised")
    func unrelatedPDF() throws {
        #expect(throws: ProtocolParserError.unrecognizedPage) {
            _ = try ProtocolPDFParser.parseSegment(data: try Self.minimalPDF(text: "2026 Some Event"))
        }
    }

    // MARK: - Skaters and titles

    @Test("every skater of the segment is read, in rank order")
    func readsSkaters() throws {
        let segment = try ProtocolPDFParser.parseSegment(data: try Fixture.pdf(women))
        #expect(segment.categorySegment == "WOMEN SHORT PROGRAM")
        // This document carries no event title line — only the segment's own.
        #expect(segment.eventName.isEmpty)
        #expect(segment.skaters.count == 12)
        #expect(segment.skaters.prefix(3).map(\.name) == ["Mao SHIMADA", "Isabeau LEVITO", "Niina PETROKINA"])
        #expect(segment.skaters.allSatisfy { $0.elements.count == 7 })
    }

    @Test("the event title and the segment line are both read when the document has them")
    func readsTitles() throws {
        let segment = try ProtocolPDFParser.parseSegment(data: try Fixture.pdf(advancedNoviceMen))
        #expect(segment.eventName == "2026 CRANBERRY CUP INTERNATIONAL")
        #expect(segment.categorySegment == "ADVANCED NOVICE BOYS SHORT PROGRAM")
        #expect(segment.skaters.count == 8)
        #expect(segment.skaters.allSatisfy { $0.elements.count == 6 })
    }

    /// A skater's name in a PDF has no club after a comma, so the whole cell is the name part.
    @Test("a PDF name has no club")
    func namesHaveNoClub() throws {
        let skater = try #require(try ProtocolPDFParser
            .parseSegment(data: try Fixture.pdf(women)).skaters.first)
        #expect(skater.namePart == "Mao SHIMADA")
        #expect(skater.club == nil)
    }

    // MARK: - Elements

    @Test("an element row is read into integer hundredths")
    func readsElements() throws {
        let skater = try #require(try ProtocolPDFParser
            .parseSegment(data: try Fixture.pdf(women)).skaters.first)
        let expected: [(index: Int, abbreviation: String, base: Int, goe: Int, panel: Int)] = [
            (1, "3A", 800, 251, 1051),
            (2, "3Fq", 530, -38, 492),
            (3, "FCSp4", 380, 87, 467),
            (4, "3Lz+3T", 1111, 177, 1288),
            (5, "StSq4", 410, 123, 533),
            (6, "LSp4", 320, 142, 462),
            (7, "CCoSp4", 420, 210, 630),
        ]
        #expect(skater.elements.count == expected.count)
        for (element, row) in zip(skater.elements, expected) {
            #expect(element.index == row.index)
            #expect(element.abbreviation == row.abbreviation)
            #expect(element.baseValue == row.base)
            #expect(element.goeValue == row.goe)
            #expect(element.panelScore == row.panel)
            #expect(element.bonusValue == 0)
        }
    }

    @Test("a Bonus column is read as bonus, not as GOE")
    func readsBonus() throws {
        let skater = try #require(try ProtocolPDFParser
            .parseSegment(data: try Fixture.pdf(advancedNoviceMen)).skaters.first)
        #expect(skater.name == "Jackey Jia Kai HUANG")

        let bonus = try #require(skater.elements.first)
        #expect(bonus.abbreviation == "3Lzb")
        #expect(bonus.baseValue == 590)
        #expect(bonus.goeValue == -118)
        #expect(bonus.bonusValue == 100)
        #expect(bonus.panelScore == 572)

        // An element with no bonus prints no bonus cell — the column is absent for that row.
        let plain = skater.elements[1]
        #expect(plain.abbreviation == "3F+2T")
        #expect(plain.bonusValue == 0)
        #expect(plain.panelScore == 671)
    }

    @Test("the second-half flag and the info markers are not values")
    func markersAreNotValues() throws {
        let skater = try #require(try ProtocolPDFParser
            .parseSegment(data: try Fixture.pdf(women)).skaters.first)
        // Row 4 is drawn as `4 | 3Lz+3T | 11.11 | x | 1.77 | … | 12.88` — the `x` is not a value.
        let secondHalf = skater.elements[3]
        #expect(secondHalf.abbreviation == "3Lz+3T")
        #expect(secondHalf.baseValue == 1111)
        #expect(secondHalf.goeValue == 177)
        // Row 2 carries `q` in the Info column; the abbreviation already holds its own marker.
        #expect(skater.elements[1].abbreviation == "3Fq")
    }

    /// The highest-value check: the page's own arithmetic against the values we extracted.
    @Test("base value plus GOE plus bonus equals the panel score on every row")
    func panelScoreInvariant() throws {
        var rows = 0
        for name in Fixture.protocolPDFs {
            let segment = try ProtocolPDFParser.parseSegment(data: try Fixture.pdf(name))
            for skater in segment.skaters {
                for element in skater.elements {
                    rows += 1
                    #expect(element.baseValue + element.goeValue + element.bonusValue == element.panelScore,
                            "\(name) \(skater.name) element \(element.index) \(element.abbreviation)")
                }
            }
        }
        #expect(rows == 84 + 48)
    }

    @Test("element numbering is validated as contiguous")
    func contiguousIndexes() throws {
        for name in Fixture.protocolPDFs {
            let segment = try ProtocolPDFParser.parseSegment(data: try Fixture.pdf(name))
            for skater in segment.skaters {
                #expect(skater.elements.map(\.index) == Array(1...skater.elements.count))
            }
        }
    }

    // MARK: - Selection

    @Test("a skater is found by name, folded for case and diacritics")
    func findsSkater() throws {
        let segment = try ProtocolPDFParser.parseSegment(data: try Fixture.pdf(women))
        #expect(try segment.skater(named: "Mao Shimada").name == "Mao SHIMADA")
        #expect(try segment.skater(named: "  mao shimada ").name == "Mao SHIMADA")
        #expect(try segment.skater(named: "Sara-Maude Dupuis").name == "Sara-Maude DUPUIS")
        #expect(throws: ProtocolParserError.self) {
            _ = try segment.skater(named: "Nobody Here")
        }
    }

    // MARK: - Importer routing

    @Test("a PDF body is routed to the PDF parser whatever the address says")
    func importerUsesPDFPath() async throws {
        // The address ends in `.html`, the body is a PDF: content decides, not the URL.
        let url = URL(string: "https://example.test/protocol.html")!
        let fetcher = RecordingFetcher(pages: [url: try Fixture.pdf(advancedNoviceMen)])
        let skater = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: url)
        #expect(skater.name == "Milo YEON")
        #expect(skater.elements.count == 6)
        #expect(await fetcher.requested == [url])
    }

    @Test("an HTML body still takes the HTML path")
    func importerUsesHTMLPath() async throws {
        let url = URL(string: "https://example.test/SEGM034.html")!
        let fetcher = RecordingFetcher(pages: [url: try Fixture.html("SEGM034.html")])
        let skater = try await ProtocolImporter(fetcher: fetcher).skater(named: "Milo Yeon", at: url)
        #expect(skater.name == "Milo Yeon, SC of Boston")
    }

    // MARK: - Helpers

    /// A one-page PDF of plain text, from CoreGraphics — a document that is not a protocol.
    private static func minimalPDF(text: String) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ProtocolParserError.unreadablePDF
        }
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ProtocolParserError.unreadablePDF
        }
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text)), context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
