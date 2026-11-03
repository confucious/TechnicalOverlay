//
//  PDFTextLayout.swift
//  ProtocolParser
//
//  Positioned text from a PDF page, reassembled into table rows
//  (`docs/architecture/protocol-parser.md` §4.8).
//
//  The ISU FS Manager protocols are tables in which every cell is an independently positioned text
//  run, and the markup carries nothing about which column a cell belongs to: the only structure is
//  where the generator put it. So extraction keeps geometry — each run's origin is transformed by
//  the current transformation matrix, runs sharing a baseline form a row, and a row's cells are
//  ordered by x. The order the runs were *drawn* in is not reading order and must not be trusted.
//

import CoreGraphics
import Foundation

/// One visual row of a PDF page: its cells, left to right, trimmed, empty ones dropped.
nonisolated struct PDFTextRow: Sendable, Equatable {
    let cells: [String]
}

/// Text extraction for the ISU FS Manager "Judges Details per Skater" PDFs.
///
/// CoreGraphics reads the file and decodes the content streams (`CGPDFScanner`); this file only
/// implements the text-extraction subset of the PDF imaging model — the graphics-state stack
/// (`q`/`Q`/`cm`), the text matrices (`BT`/`Tf`/`Td`/`TD`/`T*`/`Tm`) and the show operators
/// (`Tj`/`TJ`/`'`/`"`), plus each font's `ToUnicode` CMap to turn glyph ids back into text.
nonisolated enum PDFTextLayout {

    /// The file's header, allowing for leading junk some producers emit.
    static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
    }

    /// Every page's rows, top to bottom, in page order.
    static func rows(in data: Data) throws -> [PDFTextRow] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            throw ProtocolParserError.unreadablePDF
        }
        // An encrypted document that cannot be unlocked has no readable text.
        if document.isEncrypted && !document.isUnlocked {
            throw ProtocolParserError.unreadablePDF
        }
        guard document.numberOfPages > 0 else { throw ProtocolParserError.unreadablePDF }

        let table = operatorTable()
        var rows: [PDFTextRow] = []
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index) else { continue }
            let collector = RunCollector()
            collector.loadFonts(of: page)
            let stream = CGPDFContentStreamCreateWithPage(page)
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(collector).toOpaque())
            CGPDFScannerScan(scanner)
            rows.append(contentsOf: collector.rows())
        }
        return rows
    }

    // MARK: - Operator table

    /// Which text-showing operator a run came from; the C callback only forwards.
    fileprivate enum Operation {
        case pushTransform, popTransform, concat
        case beginText, endText, font, nextLineOffset, nextLineOffsetWithLeading
        case leading, nextLine, textMatrix
        case show, showArray, showQuoted, showDoubleQuoted
    }

    nonisolated private static func operatorTable() -> CGPDFOperatorTableRef {
        let table = CGPDFOperatorTableCreate()!

        // A `CGPDFOperatorTable` callback is a C function pointer, so it cannot capture context:
        // each registration names its operator, and the work happens in `handle(_:_:_:)`, which
        // reaches the page's collector through the callback's opaque `info` pointer.
        CGPDFOperatorTableSetCallback(table, "q", pdfPushTransform)
        CGPDFOperatorTableSetCallback(table, "Q", pdfPopTransform)
        CGPDFOperatorTableSetCallback(table, "cm", pdfConcat)
        CGPDFOperatorTableSetCallback(table, "BT", pdfBeginText)
        CGPDFOperatorTableSetCallback(table, "ET", pdfEndText)
        CGPDFOperatorTableSetCallback(table, "Tf", pdfFont)
        CGPDFOperatorTableSetCallback(table, "Td", pdfNextLineOffset)
        CGPDFOperatorTableSetCallback(table, "TD", pdfNextLineOffsetWithLeading)
        CGPDFOperatorTableSetCallback(table, "TL", pdfLeading)
        CGPDFOperatorTableSetCallback(table, "T*", pdfNextLine)
        CGPDFOperatorTableSetCallback(table, "Tm", pdfTextMatrix)
        CGPDFOperatorTableSetCallback(table, "Tj", pdfShow)
        CGPDFOperatorTableSetCallback(table, "TJ", pdfShowArray)
        CGPDFOperatorTableSetCallback(table, "'", pdfShowQuoted)
        CGPDFOperatorTableSetCallback(table, "\"", pdfShowDoubleQuoted)
        return table
    }

    nonisolated fileprivate static func handle(
        _ operation: Operation,
        _ scanner: CGPDFScannerRef,
        _ info: UnsafeMutableRawPointer?
    ) {
        guard let info else { return }
        let page = Unmanaged<RunCollector>.fromOpaque(info).takeUnretainedValue()

        switch operation {
        case .pushTransform:
            page.transformStack.append(page.transform)

        case .popTransform:
            if let previous = page.transformStack.popLast() { page.transform = previous }

        case .concat:
            let m = matrix(popNumbers(scanner, 6))
            page.transform = m.concatenating(page.transform)

        case .beginText:
            page.textMatrix = .identity
            page.lineMatrix = .identity

        case .endText:
            break

        case .font:
            var size: CGPDFReal = 0
            _ = CGPDFScannerPopNumber(scanner, &size)
            var name: UnsafePointer<CChar>?
            _ = CGPDFScannerPopName(scanner, &name)
            page.fontSize = size
            if let name { page.fontName = String(cString: name) }

        case .nextLineOffset:
            let v = popNumbers(scanner, 2)
            page.lineMatrix = page.lineMatrix.translatedBy(x: v[0], y: v[1])
            page.textMatrix = page.lineMatrix

        case .nextLineOffsetWithLeading:
            let v = popNumbers(scanner, 2)
            page.leading = -v[1]
            page.lineMatrix = page.lineMatrix.translatedBy(x: v[0], y: v[1])
            page.textMatrix = page.lineMatrix

        case .leading:
            page.leading = popNumbers(scanner, 1)[0]

        case .nextLine:
            page.lineMatrix = page.lineMatrix.translatedBy(x: 0, y: -page.leading)
            page.textMatrix = page.lineMatrix

        case .textMatrix:
            page.lineMatrix = matrix(popNumbers(scanner, 6))
            page.textMatrix = page.lineMatrix

        case .show:
            if let text = popString(scanner, page) { page.show(text) }

        case .showArray:
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            var text = ""
            for index in 0..<CGPDFArrayGetCount(array) {
                var object: CGPDFObjectRef?
                guard CGPDFArrayGetObject(array, index, &object), let object,
                      CGPDFObjectGetType(object) == .string else { continue }
                var string: CGPDFStringRef?
                guard CGPDFObjectGetValue(object, .string, &string), let string else { continue }
                text += page.decode(string)
            }
            page.show(text)

        case .showQuoted:
            page.lineMatrix = page.lineMatrix.translatedBy(x: 0, y: -page.leading)
            page.textMatrix = page.lineMatrix
            if let text = popString(scanner, page) { page.show(text) }

        case .showDoubleQuoted:
            _ = popNumbers(scanner, 2)      // word and character spacing — not used for layout here
            page.lineMatrix = page.lineMatrix.translatedBy(x: 0, y: -page.leading)
            page.textMatrix = page.lineMatrix
            if let text = popString(scanner, page) { page.show(text) }
        }
    }

    // MARK: - Operand helpers

    /// Pops `count` numbers in the order they were pushed.
    nonisolated private static func popNumbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGPDFReal] {
        var values = [CGPDFReal](repeating: 0, count: count)
        var index = count - 1
        while index >= 0 {
            _ = CGPDFScannerPopNumber(scanner, &values[index])
            index -= 1
        }
        return values
    }

    nonisolated private static func matrix(_ v: [CGPDFReal]) -> CGAffineTransform {
        CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }

    nonisolated private static func popString(_ scanner: CGPDFScannerRef, _ collector: RunCollector) -> String? {
        var string: CGPDFStringRef?
        guard CGPDFScannerPopString(scanner, &string), let string else { return nil }
        return collector.decode(string)
    }
}

// MARK: - C callbacks

// `CGPDFOperatorTable` takes C function pointers, which cannot capture context, so each operator
// gets a non-capturing function that forwards to `PDFTextLayout.handle(_:_:_:)`.

nonisolated private func pdfPushTransform(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.pushTransform, s, i)
}
nonisolated private func pdfPopTransform(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.popTransform, s, i)
}
nonisolated private func pdfConcat(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.concat, s, i)
}
nonisolated private func pdfBeginText(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.beginText, s, i)
}
nonisolated private func pdfEndText(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.endText, s, i)
}
nonisolated private func pdfFont(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.font, s, i)
}
nonisolated private func pdfNextLineOffset(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.nextLineOffset, s, i)
}
nonisolated private func pdfNextLineOffsetWithLeading(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.nextLineOffsetWithLeading, s, i)
}
nonisolated private func pdfLeading(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.leading, s, i)
}
nonisolated private func pdfNextLine(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.nextLine, s, i)
}
nonisolated private func pdfTextMatrix(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.textMatrix, s, i)
}
nonisolated private func pdfShow(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.show, s, i)
}
nonisolated private func pdfShowArray(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.showArray, s, i)
}
nonisolated private func pdfShowQuoted(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.showQuoted, s, i)
}
nonisolated private func pdfShowDoubleQuoted(_ s: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?) {
    PDFTextLayout.handle(.showDoubleQuoted, s, i)
}

// MARK: - Collection

/// One page's runs, and the fonts' CMaps needed to decode them.
///
/// A class because `CGPDFScanner` hands its callbacks an opaque pointer rather than a Swift closure
/// context.
private nonisolated final class RunCollector {
    struct Run {
        let x: Double
        let y: Double
        /// Effective size in page points, used as the row-grouping tolerance.
        let size: Double
        let text: String
    }

    var runs: [Run] = []
    var transform = CGAffineTransform.identity
    var transformStack: [CGAffineTransform] = []
    var textMatrix = CGAffineTransform.identity
    var lineMatrix = CGAffineTransform.identity
    var leading: Double = 0
    var fontSize: Double = 12
    var fontName = ""
    private var cmaps: [String: PDFToUnicodeCMap] = [:]

    /// Each font's `/ToUnicode` CMap, so glyph ids decode to text (`protocol-parser.md` §4.8).
    nonisolated func loadFonts(of page: CGPDFPage) {
        guard let dictionary = page.dictionary else { return }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return }
        var fonts: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return }

        CGPDFDictionaryApplyFunction(fonts, { key, value, info in
            guard let info else { return }
            let collector = Unmanaged<RunCollector>.fromOpaque(info).takeUnretainedValue()
            var font: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(value, .dictionary, &font), let font else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFDictionaryGetStream(font, "ToUnicode", &stream), let stream else { return }
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(stream, &format) else { return }
            collector.cmaps[String(cString: key)] = PDFToUnicodeCMap(data: data as Data)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    nonisolated func decode(_ string: CGPDFStringRef) -> String {
        guard let bytes = CGPDFStringGetBytePtr(string) else { return "" }
        let length = CGPDFStringGetLength(string)
        let raw = Array(UnsafeBufferPointer(start: bytes, count: length))

        // No `/ToUnicode` on this font: its codes are single-byte character codes of a simple font.
        // Latin-1 reads them as text; these protocols always ship a CMap, so this is the fallback
        // that keeps an unrelated PDF readable enough to be rejected as "not a protocol".
        guard let cmap = cmaps[fontName] else {
            return String(bytes: raw, encoding: .isoLatin1) ?? ""
        }

        let width = cmap.codeBytes
        var text = ""
        var index = 0
        while index < raw.count {
            var code = 0
            var offset = 0
            while offset < width && index + offset < raw.count {
                code = code << 8 | Int(raw[index + offset])
                offset += 1
            }
            index += width
            text += cmap.text(for: code)
        }
        return text
    }

    /// Records one drawn string at its origin in page coordinates.
    nonisolated func show(_ text: String) {
        guard !text.isEmpty else { return }
        let rendering = textMatrix.concatenating(transform)
        let origin = CGPoint(x: rendering.tx, y: rendering.ty)
        let scale = (rendering.a * rendering.d - rendering.b * rendering.c).magnitude.squareRoot()
        runs.append(Run(x: Double(origin.x), y: Double(origin.y),
                        size: Double(fontSize) * Double(scale), text: text))
    }

    /// Rows, top to bottom, each cell ordered left to right.
    nonisolated func rows() -> [PDFTextRow] {
        guard !runs.isEmpty else { return [] }

        var groups: [[Run]] = []
        for run in runs.sorted(by: { $0.y > $1.y }) {
            if var last = groups.last, let reference = last.first,
               abs(reference.y - run.y) < max(1.0, 0.4 * reference.size) {
                last.append(run)
                groups[groups.count - 1] = last
            } else {
                groups.append([run])
            }
        }

        return groups.compactMap { group in
            let cells = group.sorted { $0.x < $1.x }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cells.isEmpty ? nil : PDFTextRow(cells: cells)
        }
    }
}

// MARK: - ToUnicode CMap

/// One font's `ToUnicode` CMap: glyph code → text.
///
/// PDFsharp writes this producer's CMap with the *literal* characters `\r\n` between entries rather
/// than line breaks, so entries are tokenised rather than split into lines.
private struct PDFToUnicodeCMap {
    private let entries: [Int: String]
    let codeBytes: Int

    init(data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        var entries: [Int: String] = [:]

        // A simple font uses one-byte codes; the Identity-H CID fonts these protocols use do not.
        var codeBytes = 2
        if let range = text.range(of: "begincodespacerange") {
            let parts = text[range.upperBound...].components(separatedBy: "<")
            if parts.count > 2, parts[2].components(separatedBy: ">")[0].count <= 2 { codeBytes = 1 }
        }
        self.codeBytes = codeBytes

        for body in Self.bodies("beginbfchar", "endbfchar", in: text) {
            let tokens = Self.tokens(body)
            var index = 0
            while index + 1 < tokens.count {
                if case .hex(let source) = tokens[index], case .hex(let destination) = tokens[index + 1],
                   let code = Int(source, radix: 16) {
                    entries[code] = Self.string(destination)
                }
                index += 2
            }
        }

        for body in Self.bodies("beginbfrange", "endbfrange", in: text) {
            let tokens = Self.tokens(body)
            var index = 0
            while index + 2 < tokens.count {
                guard case .hex(let lowHex) = tokens[index], case .hex(let highHex) = tokens[index + 1],
                      let low = Int(lowHex, radix: 16), let high = Int(highHex, radix: 16) else {
                    index += 1
                    continue
                }
                switch tokens[index + 2] {
                case .open:
                    // `<low> <high> [ <destination>… ]` — one destination per code.
                    var code = low
                    var cursor = index + 3
                    while cursor < tokens.count, case .hex(let destination) = tokens[cursor], code <= high {
                        entries[code] = Self.string(destination)
                        code += 1
                        cursor += 1
                    }
                    if cursor < tokens.count, case .close = tokens[cursor] { cursor += 1 }
                    index = cursor
                case .hex(let destinationHex):
                    // `<low> <high> <destination>` — destinations count up from the first.
                    guard let base = Int(destinationHex, radix: 16) else {
                        index += 3
                        continue
                    }
                    for offset in 0...(high - low) {
                        entries[low + offset] = Self.string(String(format: "%04X", base + offset))
                    }
                    index += 3
                case .close:
                    index += 1
                }
            }
        }
        self.entries = entries
    }

    func text(for code: Int) -> String { entries[code] ?? "" }

    private enum Token { case hex(String), open, close }

    private static func bodies(_ start: String, _ end: String, in text: String) -> [String] {
        text.components(separatedBy: start).dropFirst().compactMap {
            $0.components(separatedBy: end).first
        }
    }

    private static func tokens(_ body: String) -> [Token] {
        var tokens: [Token] = []
        var index = body.startIndex
        while index < body.endIndex {
            switch body[index] {
            case "<":
                guard let close = body[index...].firstIndex(of: ">") else { return tokens }
                tokens.append(.hex(String(body[body.index(after: index)..<close])))
                index = body.index(after: close)
            case "[":
                tokens.append(.open)
                index = body.index(after: index)
            case "]":
                tokens.append(.close)
                index = body.index(after: index)
            default:
                index = body.index(after: index)
            }
        }
        return tokens
    }

    /// A destination is UTF-16BE, four hex digits per `UInt16`.
    private static func string(_ hex: String) -> String {
        var units: [UInt16] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 4, limitedBy: hex.endIndex) {
            if let unit = UInt16(hex[index..<next], radix: 16) { units.append(unit) }
            index = next
        }
        return String(decoding: units, as: UTF16.self)
    }
}
