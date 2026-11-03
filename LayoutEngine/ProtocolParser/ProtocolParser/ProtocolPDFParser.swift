//
//  ProtocolPDFParser.swift
//  ProtocolParser
//
//  The ISU FS Manager "Judges Details per Skater" PDF (`docs/architecture/protocol-parser.md`
//  §2.3, §4.8–§4.9). Same model, same units and the same sanity check as the HTML path: the page's
//  cells are read positionally, so nothing here re-derives values the page already states.
//

import Foundation

public nonisolated enum ProtocolPDFParser {

    /// A PDF, by its header rather than its URL — a protocol address can serve either kind.
    public static func isPDF(_ data: Data) -> Bool {
        PDFTextLayout.isPDF(data)
    }

    /// Reads a whole PDF into skaters and elements.
    ///
    /// A skater's section opens with its identity line — rank, name, nation, starting number and the
    /// four segment scores, all on one row — and its elements follow until the next identity line
    /// (`protocol-parser.md` §4.9). Rows between them that are not elements (the totals line, the
    /// program-components block, the page header a page break repeats) are skipped by shape.
    public static func parseSegment(data: Data) throws -> ProtocolSegment {
        let rows = try PDFTextLayout.rows(in: data)
        guard let title = rows.firstIndex(where: { row in
            row.cells.contains(where: { $0.hasPrefix("JUDGES DETAILS PER SKATER") })
        }) else {
            throw ProtocolParserError.unrecognizedPage
        }

        // The segment line sits directly under the title, and the event title — when this document
        // has one — sits directly above it (`protocol-parser.md` §4.9). The column headers follow the
        // segment line, so the title's neighbours, not "the lines before the first skater", are what
        // carry these.
        let titleLine = { (offset: Int) -> String in
            let index = title + offset
            guard rows.indices.contains(index) else { return "" }
            return rows[index].cells.joined(separator: " ")
        }
        let categorySegment = titleLine(1)
        let eventName = title > 0 ? titleLine(-1) : ""

        var skaters: [ProtocolSkater] = []
        var open: Block?

        for row in rows {
            if let identity = identity(from: row) {
                if let finished = open {
                    skaters.append(try skater(named: finished.name, elements: finished.elements))
                }
                open = Block(name: identity.name, elements: [])
                continue
            }
            guard var block = open else { continue }
            if let element = try element(from: row, skater: block.name) {
                block.elements.append(element)
                open = block
            }
        }
        if let finished = open {
            skaters.append(try skater(named: finished.name, elements: finished.elements))
        }
        guard !skaters.isEmpty else { throw ProtocolParserError.unrecognizedPage }

        return ProtocolSegment(
            eventName: eventName,
            categorySegment: categorySegment,
            skaters: skaters)
    }

    // MARK: - Rows

    private struct Block {
        let name: String
        var elements: [ProtocolElement]
    }

    private struct Identity {
        let rank: Int
        let name: String
        let nation: String
        let startingNumber: Int
    }

    /// The identity line: `rank name nation starting number total tes pcs deductions`, right-anchored
    /// on the four scores so a name made of several runs still reads as one name
    /// (`protocol-parser.md` §4.9).
    private static func identity(from row: PDFTextRow) -> Identity? {
        let cells = row.cells
        guard cells.count >= 7, let rank = Int(cells[0]) else { return nil }
        guard cells.suffix(4).allSatisfy(ProtocolNumber.isDecimal) else { return nil }
        guard let startingNumber = Int(cells[cells.count - 5]) else { return nil }
        let nation = cells[cells.count - 6]
        guard nation.range(of: "^[A-Z0-9]{2,5}$", options: .regularExpression) != nil else { return nil }
        let name = cells[1..<(cells.count - 6)].joined(separator: " ")
        guard !name.isEmpty else { return nil }
        return Identity(rank: rank, name: name, nation: nation, startingNumber: startingNumber)
    }

    /// An element row: `index, abbreviation, info…, base, [x], goe, judges…, [bonus], panel`.
    ///
    /// The `info` and `x` columns are never read (`protocol-parser.md` §10a); of the numeric cells,
    /// the panel score is the last, and the ones before it are base, GOE and — when the page has a
    /// bonus column — bonus, in that order.
    private static func element(from row: PDFTextRow, skater: String) throws -> ProtocolElement? {
        let cells = row.cells
        guard cells.count >= 4, let index = Int(cells[0]) else { return nil }
        let abbreviation = cells[1]
        guard !abbreviation.isEmpty, !ProtocolNumber.isDecimal(abbreviation) else { return nil }

        let printed = cells.dropFirst(2).filter(ProtocolNumber.isDecimal)
        // Base value and panel score are required; anything less is a different kind of row.
        guard printed.count >= 2 else { return nil }
        guard printed.count <= 4 else {
            throw ProtocolParserError.malformedElementRow(
                skater: skater, index: String(index), reason: "more score columns than expected")
        }
        let values = printed.compactMap(ProtocolNumber.hundredths)
        guard values.count == printed.count else {
            throw ProtocolParserError.malformedElementRow(
                skater: skater, index: String(index), reason: "a score is not a number")
        }

        return ProtocolElement(
            index: index,
            abbreviation: abbreviation,
            baseValue: values[0],
            goeValue: values.count > 2 ? values[1] : 0,
            bonusValue: values.count > 3 ? values[2] : 0,
            panelScore: values[values.count - 1])
    }

    private static func skater(named name: String, elements: [ProtocolElement]) throws -> ProtocolSkater {
        guard !elements.isEmpty else { throw ProtocolParserError.elementTableMissing(skater: name) }
        for (offset, element) in elements.enumerated() where element.index != offset + 1 {
            throw ProtocolParserError.malformedElementRow(
                skater: name,
                index: String(element.index),
                reason: "element numbering is not contiguous from 1")
        }
        return ProtocolSkater(name: name, elements: elements)
    }
}
