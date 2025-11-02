//
//  OverlayDataDocument.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/31/25.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct OverlayDataDocument: FileDocument {
    enum Errors: Error {
        case overlayDataNotSetToWrite
        case unableToReadData
        case versionUnsupported
    }
    static let fileType = UTType(filenameExtension: "tod", conformingTo: .json)!
    static var readableContentTypes: [UTType] = [fileType]
    static var writableContentTypes: [UTType] = [fileType]
        
    var overlayData: OverlayData?

    static func read(url: URL) throws -> OverlayData {
        guard url.startAccessingSecurityScopedResource()
        else {
            throw Errors.unableToReadData
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        let data = try Data(contentsOf: url)
        return try decode(data: data)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents
        else {
            throw Errors.unableToReadData
        }
        overlayData = try Self.decode(data: data)
    }
    
    private static func decode(data: Data) throws -> OverlayData {
        let versionedData = try JSONDecoder().decode(
            VersionedOverlayData.self,
            from: data
        )
        guard versionedData.version == 1
        else {
            throw Errors.versionUnsupported
        }
        return try versionedData.getOverlayData()
    }

    init(overlayDataForSave data: OverlayData) {
        self.overlayData = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let overlayData else {
            throw Errors.overlayDataNotSetToWrite
        }
        let versionedData = try VersionedOverlayData(overlayData: overlayData)
        let data = try JSONEncoder().encode(versionedData)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct VersionedOverlayData: nonisolated Codable {
    enum Errors: Error {
        case unknownVersion(Int)
        case unableToDecodeJson
        case unableToEncodeJson
    }
    var version: Int = 1
    var overlayJson: String
    
    init(overlayData: OverlayData) throws {
        let jsonData = try JSONEncoder().encode(overlayData)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw Errors.unableToEncodeJson
        }
        self.overlayJson = json
    }
    
    func getOverlayData() throws -> OverlayData {
        switch version {
        case 1:
            guard let jsonData = overlayJson.data(using: .utf8) else {
                throw Errors.unableToDecodeJson
            }
            let data = try JSONDecoder().decode(
                OverlayData.self,
                from: jsonData
            )
            return data
        default:
            throw Errors.unknownVersion(version)
        }
    }
}
