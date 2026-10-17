//
//  ExportSession.swift
//  VideoProcessor
//
//  A configured export the caller performs when it is ready.
//

import AVFoundation
import Foundation

extension VideoComposer {

    /// Wraps `AVAssetExportSession` with async progress — the file appears only when the caller
    /// performs the export.
    public struct ExportSession {
        let exportSession: AVAssetExportSession
        let outputUrl: URL
        let outputFileType: AVFileType
        public let exportState: any AsyncSequence<AVAssetExportSession.State, Never>
        
        init(
            exportSession: AVAssetExportSession,
            outputUrl: URL,
            outputFileType: AVFileType,
        ) {
            self.exportSession = exportSession
            self.outputUrl = outputUrl
            self.outputFileType = outputFileType
            self.exportState = exportSession.states(updateInterval: 0.1)
        }
        
        /// Writes the composition to `outputUrl`, throwing on failure so the caller can surface it.
        public func performExport() async throws {
            try await exportSession.export(to: outputUrl, as: outputFileType)
        }
    }
}
