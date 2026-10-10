import ProjectDescription

// MARK: - Shared settings

let deploymentTarget = DeploymentTargets.iOS("26.0")
let destinations: Destinations = [.iPhone, .iPad]

// Shared base settings for all targets (matches the previous hand-maintained projects).
let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.0",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "9MY93JMP2W",
]

// The app declares its `.tojson` document type (UTType). Exported only: the same identifier
// must not also be in UTImportedTypeDeclarations. See docs/ARCHITECTURE.md §4 (Persistence).
let appInfoPlist: InfoPlist = .extendingDefault(with: [
    "UTExportedTypeDeclarations": [
        [
            "UTTypeConformsTo": ["public.json"],
            "UTTypeDescription": "Technical Overlay Data",
            "UTTypeIconFiles": [],
            "UTTypeIdentifier": "org.cjas.jhsu.overlay-document",
            "UTTypeTagSpecification": ["public.filename-extension": ["tojson"]],
        ]
    ],
    "LSApplicationCategoryType": "public.app-category.sports",
    "UIApplicationSceneManifest": [
        "UIApplicationSupportsMultipleScenes": false,
    ],
    "UIApplicationSupportsIndirectInputEvents": true,
    "UILaunchScreen": [:],
    "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ],
    "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ],
])

let appSettings = Settings.settings(
    base: baseSettings.merging([
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CURRENT_PROJECT_VERSION": "5",
        "MARKETING_VERSION": "1.0",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    ]) { _, new in new }
)

// MARK: - Targets

private let appTarget = Target.target(
    name: "TechnicalOverlay",
    destinations: destinations,
    product: .app,
    bundleId: "org.cjas.technical-overlay",
    deploymentTargets: deploymentTarget,
    infoPlist: appInfoPlist,
    sources: ["TechnicalOverlay/TechnicalOverlay/**/*.swift"],
    resources: ["TechnicalOverlay/TechnicalOverlay/Assets.xcassets"],
    dependencies: [
        .target(name: "LayoutEngine"),
        .target(name: "VideoProcessor"),
    ],
    settings: appSettings
)

private let appTestsTarget = Target.target(
    name: "TechnicalOverlayTests",
    destinations: destinations,
    product: .unitTests,
    bundleId: "org.cjas.jhsu.TechnicalOverlayTests",
    deploymentTargets: deploymentTarget,
    sources: ["TechnicalOverlay/TechnicalOverlayTests/**/*.swift"],
    dependencies: [.target(name: "TechnicalOverlay")],
    settings: .settings(base: baseSettings)
)

private let appUITestsTarget = Target.target(
    name: "TechnicalOverlayUITests",
    destinations: destinations,
    product: .uiTests,
    bundleId: "org.cjas.jhsu.TechnicalOverlayUITests",
    deploymentTargets: deploymentTarget,
    sources: ["TechnicalOverlay/TechnicalOverlayUITests/**/*.swift"],
    dependencies: [.target(name: "TechnicalOverlay")],
    settings: .settings(base: baseSettings)
)

private let layoutEngineTarget = Target.target(
    name: "LayoutEngine",
    destinations: destinations,
    product: .framework,
    bundleId: "org.cjas.jhsu.LayoutEngine",
    deploymentTargets: deploymentTarget,
    sources: ["LayoutEngine/LayoutEngine/**/*.swift"],
    settings: .settings(base: baseSettings)
)

private let layoutEngineTestsTarget = Target.target(
    name: "LayoutEngineTests",
    destinations: destinations,
    product: .unitTests,
    bundleId: "org.cjas.jhsu.LayoutEngineTests",
    deploymentTargets: deploymentTarget,
    sources: ["LayoutEngine/LayoutEngineTests/**/*.swift"],
    dependencies: [.target(name: "LayoutEngine")],
    settings: .settings(base: baseSettings)
)

private let videoProcessorTarget = Target.target(
    name: "VideoProcessor",
    destinations: destinations,
    product: .framework,
    bundleId: "org.cjas.jhsu.VideoProcessor",
    deploymentTargets: deploymentTarget,
    sources: ["LayoutEngine/VideoProcessor/VideoProcessor/**/*.swift"],
    settings: .settings(base: baseSettings)
)

private let videoProcessorTestsTarget = Target.target(
    name: "VideoProcessorTests",
    destinations: destinations,
    product: .unitTests,
    bundleId: "org.cjas.jhsu.VideoProcessorTests",
    deploymentTargets: deploymentTarget,
    sources: ["LayoutEngine/VideoProcessor/VideoProcessorTests/**/*.swift"],
    dependencies: [.target(name: "VideoProcessor")],
    settings: .settings(base: baseSettings)
)

private let protocolParserTarget = Target.target(
    name: "ProtocolParser",
    destinations: destinations,
    product: .framework,
    bundleId: "org.cjas.jhsu.ProtocolParser",
    deploymentTargets: deploymentTarget,
    sources: ["LayoutEngine/ProtocolParser/ProtocolParser/**/*.swift"],
    settings: .settings(base: baseSettings)
)

private let protocolParserTestsTarget = Target.target(
    name: "ProtocolParserTests",
    destinations: destinations,
    product: .unitTests,
    bundleId: "org.cjas.jhsu.ProtocolParserTests",
    deploymentTargets: deploymentTarget,
    sources: ["LayoutEngine/ProtocolParser/ProtocolParserTests/**/*.swift"],
    dependencies: [.target(name: "ProtocolParser")],
    settings: .settings(base: baseSettings)
)

// MARK: - Project

let project = Project(
    name: "TechnicalOverlay",
    organizationName: "cjas",
    targets: [
        appTarget,
        appTestsTarget,
        appUITestsTarget,
        layoutEngineTarget,
        layoutEngineTestsTarget,
        videoProcessorTarget,
        videoProcessorTestsTarget,
        protocolParserTarget,
        protocolParserTestsTarget,
    ]
)
