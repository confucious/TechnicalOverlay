//
//  MainView.swift
//  TechnicalOverlay
//
//  Created by Jerry Hsu on 10/19/25.
//

import SwiftUI
import AVFoundation
import AVKit
import VideoProcessor

//enum State {
//    case waitingForVideo
//    case videoLoaded
//}

struct MainView: View {

    enum Destination {
        case editSlides
    }

    @State private var model = MainViewModel()
    @State private var fileSelectShowing = false
    @State private var saveFileShowing = false
    @State private var loadOverlayDataShowing = false
    @State private var saveOverlayDataShowing = false
    @State private var clearSlidesShowing = false
    private var showProgressModal: Binding<Bool> {
        Binding(
            get: {
                model.export.phase != .idle
            },
            set: {
                if !$0 {
                    model.export.phase = .idle
                }
            }
        )
    }

    /// Clearance between the render indicator and the bottom edge of the video, in points. AVKit's
    /// control cluster — the scrubbing control included — sits in that band, so the indicator is
    /// lifted clear of it rather than derived from the video's size.
    private static let queueStatusBottomInset: CGFloat = 72

    /// Dot + label for the background chunk queue, drawn over the video's bottom-right corner.
    private var queueStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.pipeline.status.indicatorColor)
                .frame(width: 10, height: 10)
            Text(model.pipeline.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // The video underneath is arbitrary, so the label needs its own ground.
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.pipeline.status.accessibilityDescription)
    }

    /// Overlay look toggle: the technical pane's element box row can be hidden, which moves the
    /// name, score and total rows up.
    private var elementBoxToggle: some View {
        Toggle(
            "Element boxes",
            isOn: Binding(
                get: { model.scoring.showsElementBox },
                set: { model.setShowsElementBox($0) }
            )
        )
        .toggleStyle(.switch)
        .font(.callout)
    }

    private var loadSlidesButton: some View {
        Button("Load Slides") {
            loadOverlayDataShowing.toggle()
        }
        .buttonStyle(.bordered)
        .fileImporter(
            isPresented: $loadOverlayDataShowing,
            allowedContentTypes: [OverlayDataDocument.fileType]) { result in
                switch result {
                case let .success(url):
                    do {
                        let newData = try OverlayDataDocument.read(url: url)
                        model.scoring.update(from: newData)
                        model.scoring.save()
                    } catch {
                        print("data load error: \(error)")
                    }
                case let .failure(error):
                    print("data load error: \(error)")
                }
            }
    }

    private var saveSlidesButton: some View {
        Button("Save Slides") {
            saveOverlayDataShowing.toggle()
        }
        .buttonStyle(.bordered)
        .fileExporter(
            isPresented: $saveOverlayDataShowing,
            document: OverlayDataDocument(overlayDataForSave: model.scoring),
            contentType: OverlayDataDocument.fileType,
            defaultFilename: model.scoring.skaterFullName) { result in
                print("overlay data save: \(result)")
            }
    }

    private var editSlidesButton: some View {
        NavigationLink("Edit Slides", value: Destination.editSlides)
            .buttonStyle(.bordered)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .editSlides:
                    ScoringListView(state: model.scoring)
                }
            }
    }

    private var clearSlidesButton: some View {
        Button("Clear Slides") {
            clearSlidesShowing = true
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(model.scoring.isEmpty)
        .confirmationDialog(
            "Clear all slides?",
            isPresented: $clearSlidesShowing,
            titleVisibility: .visible
        ) {
            Button("Clear Slides", role: .destructive) {
                model.clearSlides()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The skater names, intro slides and elements stored on this device are deleted. This can't be undone.")
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                if let player = model.player {
                    VideoPlayer(player: player)
                        .overlay(alignment: .bottomTrailing) {
                            queueStatusIndicator
                                .padding(.trailing, 16)
                                .padding(.bottom, Self.queueStatusBottomInset)
                                // Status only — must not swallow taps meant for the player controls.
                                .allowsHitTesting(false)
                        }
                }
                HStack {
                    Button("Load Video") {
                        fileSelectShowing.toggle()
                    }
                    .buttonStyle(.bordered)
                    .fileImporter(
                        isPresented: $fileSelectShowing,
                        allowedContentTypes: [.movie]) { result in
                            switch result {
                            case let .success(fileUrl):
                                model.assetUrl = fileUrl
                            case let .failure(error):
                                print(error)
                            }
                        }
                    Button("Save Video") {
                        // Ask for the destination FIRST: nothing else is presented yet, so the save
                        // panel can't collide with the progress sheet, and the export can write
                        // straight to the chosen URL — no temp file, and no copying a multi-GB
                        // video through memory in a FileWrapper afterwards.
                        saveFileShowing = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.saveVideoDisabled)
                    .fileExporter(
                        isPresented: $saveFileShowing,
                        document: SaveDestinationPlaceholder(),
                        contentType: .quickTimeMovie,
                        defaultFilename: model.outputFilename
                    ) { result in
                        switch result {
                        case let .success(destinationURL):
                            Task { await model.exportScoredVideo(to: destinationURL) }
                        case let .failure(error):
                            print("Save panel dismissed without a destination: \(error)")
                        }
                    }
                    .sheet(isPresented: showProgressModal, content: {
                        VStack {
                            switch model.export.phase {
                            case .idle:
                                // The sheet is only up when the phase isn't idle.
                                EmptyView()

                            case .rendering:
                                if let progress = model.pipeline.progress {
                                    ProgressView(
                                        "Rendering overlay chunks (\(progress.completed)/\(progress.total))",
                                        value: Double(progress.completed),
                                        total: Double(max(progress.total, 1))
                                    ).padding(20.0)
                                } else {
                                    ProgressView("Rendering overlay chunks…").padding(20.0)
                                }

                            case .stitching:
                                if let stitchProgress = model.export.stitchingProgress {
                                    ProgressView(
                                        "Stitching final video...",
                                        value: stitchProgress.fractionCompleted
                                    ).padding(20.0)
                                } else {
                                    // No progress tick yet — don't call that an error.
                                    ProgressView("Stitching final video...").padding(20.0)
                                }

                            case .done:
                                Text("Export complete")
                                Button("Close") {
                                    model.export.phase = .idle
                                }

                            case let .failed(message):
                                Text(message)
                                Button("Close") {
                                    model.export.phase = .idle
                                }
                            }
                        }.interactiveDismissDisabled()
                    })
                }
                elementBoxToggle
                    .fixedSize()
                if !model.scoring.isEmpty {
                    ScrollView {
                        TimeSettingsView(
                            state: model.scoring,
                            playhead: model.player.map { player in
                                Playhead(
                                    getTime: {
                                        let time = player.currentTime()
                                        return time.isNumeric ? time.seconds : nil
                                    },
                                    seekTo: { time in
                                        player.seek(
                                            to: CMTime(
                                                seconds: time,
                                                preferredTimescale: 600
                                            )
                                        )
                                    }
                                )
                            },
                            timeUpdated: {
                                model.generateSlides()
                            }
                        ).padding(
                            .init(
                                top: 0.0,
                                leading: 10.0,
                                bottom: 0.0,
                                trailing: 10.0
                            )
                        )
                    }
                }
                // Four labels don't fit one row on a phone in portrait, so the row drops to two
                // when the single line would squeeze a label onto two.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        loadSlidesButton
                        saveSlidesButton
                        editSlidesButton
                        clearSlidesButton
                    }
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            loadSlidesButton
                            saveSlidesButton
                        }
                        HStack(spacing: 8) {
                            editSlidesButton
                            clearSlidesButton
                        }
                    }
                }
            }
        }
        .onAppear {
            model.generateSlides()
        }
    }
}

/// A zero-byte stand-in used only to obtain a destination URL from the save panel.
///
/// SwiftUI's `fileExporter` is document-based: it writes the document you hand it to wherever the
/// user chooses and reports that URL back. Handing it an empty document lets the app ask for the
/// destination *before* rendering, then write the real exported video over it — no temp file, and
/// no reading a multi-GB video into memory just to copy it.
///
/// The export must delete that placeholder first: `AVAssetExportSession` refuses to write over an
/// existing file ("Cannot Save — the requested file name is already in use").
struct SaveDestinationPlaceholder: FileDocument {

    static var readableContentTypes: [UTType] = [.movie]
    static var writableContentTypes: [UTType] = [.movie, .quickTimeMovie]

    init() {}

    init(configuration: ReadConfiguration) throws {
        // Never opened for reading — this document exists to name a destination.
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}

#Preview {
    MainView()
}

// MARK: - Queue status presentation

extension RenderPipeline.Status {

    /// Yellow while the queue has work, green once it is fully rendered and idle. Grey when
    /// there's no video to render at all (nothing is "fully rendered" yet).
    var indicatorColor: Color {
        switch self {
        case .noVideo: return .gray
        case .processing: return .yellow
        case .idle: return .green
        }
    }

    var label: String {
        switch self {
        case .noVideo: return "No video"
        case .processing: return "Rendering"
        case .idle: return "Rendered"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .noVideo: return "No video loaded, nothing to render"
        case .processing: return "Rendering overlay chunks in the background"
        case .idle: return "All overlay chunks are rendered"
        }
    }
}
