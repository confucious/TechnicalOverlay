//
//  ProtocolImportModelTests.swift
//  TechnicalOverlayTests
//
//  The import flow the "Import Protocol" button starts: URL validation, the skater-name guard, the
//  merge on success, and the message shown on failure.
//

import Foundation
import ProtocolParser
import Testing
@testable import TechnicalOverlay

private struct StubFetcher: ProtocolFetching {
    let page: String
    let failure: ProtocolParserError?

    nonisolated func fetch(_ url: URL) async throws -> String {
        if let failure { throw failure }
        return page
    }

    /// A minimal segment detail page: enough for the module to classify and parse it.
    static let detailPage = """
        <html><body>
        <h2 class=catseg>Test Segment / Free Skate</h2>
        <TABLE class=sum><TBODY>
        <TR><TD class=name>Milo Yeon, SC of Boston</TD></TR>
        </TBODY></TABLE>
        <TABLE class=elm><THEAD>
        <TR><TH class=num>#</TH><TH class=elem>Elements</TH><TH class=bv>Base</TH><TH class=goe>GOE</TH><TH class=ref>Bonus</TH><TH class=psl>Score</TH></TR>
        </THEAD><TBODY>
        <TR><TD class=num>1</TD><TD class=elem>2Lz</TD><TD class=bv>2.10</TD><TD class=goe>0.42</TD><TD class=ref></TD><TD class=psv>2.52</TD></TR>
        <TR><TD class=num>2</TD><TD class=elem>3T</TD><TD class=bv>4.62</TD><TD class=goe>0.84</TD><TD class=ref>1.00</TD><TD class=psv>6.46</TD></TR>
        </TBODY></TABLE>
        </body></html>
        """
}

@Suite("Protocol import flow")
struct ProtocolImportModelTests {
    private let url = "https://ijs.usfigureskating.org/leaderboard/results/2026/36683/SEGM034.html"

    private func model(page: String = StubFetcher.detailPage, failure: ProtocolParserError? = nil) -> ProtocolImportModel {
        ProtocolImportModel(importer: ProtocolImporter(fetcher: StubFetcher(page: page, failure: failure)))
    }

    private func data(name: String = "Milo Yeon") -> OverlayData {
        OverlayData(skaterFullName: name)
    }

    @Test("a valid protocol URL is accepted, whitespace and all")
    func acceptsValidURL() {
        #expect(ProtocolImportModel.url(from: "  \(url)  ")?.absoluteString == url)
    }

    @Test("something that is not an http address is rejected")
    func rejectsNonURL() {
        #expect(ProtocolImportModel.url(from: "") == nil)
        #expect(ProtocolImportModel.url(from: "   ") == nil)
        #expect(ProtocolImportModel.url(from: "ijs.usfigureskating.org/SEGM034.html") == nil)
        #expect(ProtocolImportModel.url(from: "file:///tmp/SEGM034.html") == nil)
    }

    @Test("importing without a URL explains what is needed and changes nothing")
    func missingURL() async {
        let data = data()
        data.elementScores = [ElementData(name: "Kept", baseValue: 100, goeValue: 10, bonusValue: 0, displayTime: 3)]

        let model = model()
        model.urlString = ""
        await model.importElements(into: data)

        #expect(model.errorMessage != nil)
        #expect(data.elementScores.map(\.name) == ["Kept"])
    }

    @Test("importing without a skater name explains what is needed and changes nothing")
    func missingSkaterName() async {
        let data = data(name: "   ")
        let model = model()
        model.urlString = url

        await model.importElements(into: data)

        #expect(model.errorMessage != nil)
        #expect(data.elementScores.isEmpty)
    }

    @Test("a successful import merges the elements and keeps the timing already set")
    func successfulImport() async {
        let data = data()
        data.elementScores = [
            ElementData(name: "Typed By Hand", baseValue: 100, goeValue: 10, bonusValue: 0, displayTime: 12.5),
        ]
        let model = model()
        model.urlString = url

        await model.importElements(into: data)

        #expect(model.errorMessage == nil)
        #expect(data.elementScores.count == 2)
        #expect(data.elementScores[0].name == "2Lz")
        #expect(data.elementScores[0].baseValue == 210)
        #expect(data.elementScores[0].displayTime == 12.5)      // the timeline survives
        #expect(data.elementScores[1].name == "3T")
        #expect(data.elementScores[1].bonusValue == 100)
        #expect(data.elementScores[1].displayTime == nil)       // appended, untimed
    }

    @Test("a page without judge details reports the published-status message")
    func unpublishedDetails() async {
        let data = data()
        let model = model(failure: .detailLinkMissing)
        model.urlString = url

        await model.importElements(into: data)

        #expect(data.elementScores.isEmpty)
        #expect(model.errorMessage == ProtocolParserError.detailLinkMissing.errorDescription)
    }

    @Test("a skater who is not on the page reports the available names")
    func skaterNotFound() async {
        let data = data(name: "Nobody Here")
        let model = model()
        model.urlString = url

        await model.importElements(into: data)

        #expect(data.elementScores.isEmpty)
        #expect(model.errorMessage?.contains("Milo Yeon, SC of Boston") == true)
    }

    @Test("the import is not in progress once it finishes")
    func finishesImporting() async {
        let model = model()
        model.urlString = url
        await model.importElements(into: data())
        #expect(model.isImporting == false)
    }
}
