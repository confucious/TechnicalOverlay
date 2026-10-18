//
//  ChunkQueueShutdownTests.swift
//  VideoProcessorTests
//
//  What `ChunkQueue.shutdown()` owes the filesystem: the chunks a queue rendered are its own, and
//  nothing is still writing into one when it goes.
//

import Testing
import AVFoundation
import CoreImage
import Foundation
@testable import VideoProcessor

// MARK: - Renderers that write real files

/// Writes a small file per chunk, so the queue's cleanup has something real to delete.
final class FileWritingRenderer: ChunkRendererProtocol, @unchecked Sendable {

    private let directory: URL
    private(set) var written: [URL] = []

    init(directory: URL) {
        self.directory = directory
    }

    func render(_ chunk: Chunk) async -> URL? {
        let url = directory.appendingPathComponent("chunk_\(chunk.id.uuidString).mov")
        try? Data("chunk".utf8).write(to: url)
        written.append(url)
        return url
    }
}

/// Writes the file first, then takes a while to finish — so a shutdown lands mid-render.
final class SlowFileWritingRenderer: ChunkRendererProtocol, @unchecked Sendable {

    private let directory: URL
    private let delay: Duration

    init(directory: URL, delay: Duration) {
        self.directory = directory
        self.delay = delay
    }

    func render(_ chunk: Chunk) async -> URL? {
        let url = directory.appendingPathComponent("chunk_\(chunk.id.uuidString).mov")
        try? Data("chunk".utf8).write(to: url)
        try? await Task.sleep(for: delay)
        return url
    }
}

// MARK: - Tests

@Suite struct ChunkQueueShutdownTests {

    private let transitionTime = CMTime(seconds: 1, preferredTimescale: 1)
    private let videoDuration = CMTime(seconds: 20, preferredTimescale: 1)
    private var slide: Slide {
        Slide(image: CIImage.clear, startTime: CMTime(seconds: 5, preferredTimescale: 1))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChunkQueueShutdownTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func shutdownDeletesWhatTheQueueRendered() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderer = FileWritingRenderer(directory: directory)
        let queue = ChunkQueue(renderer: renderer, transitionTime: transitionTime)

        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.waitForCompletion()

        let rendered = await queue.validChunks()
        #expect(!rendered.isEmpty)
        #expect(!renderer.written.isEmpty)
        #expect(renderer.written.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        await queue.shutdown()

        let chunks = await queue.chunks
        #expect(chunks.isEmpty)
        #expect(renderer.written.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func shutdownWaitsForTheRenderInFlightBeforeDeleting() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderer = SlowFileWritingRenderer(directory: directory, delay: .milliseconds(200))
        let queue = ChunkQueue(renderer: renderer, transitionTime: transitionTime)

        // `enqueue` returns while its drain renders in the background, so this lands mid-render.
        await queue.enqueue(slides: [slide], videoDuration: videoDuration)
        await queue.shutdown()

        let chunks = await queue.chunks
        #expect(chunks.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(leftovers.isEmpty)
    }
}
