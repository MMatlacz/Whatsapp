// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatsAppTranslatorCore",
    platforms: [
        .macOS(.v13),
        // Swift 6.0's PackageDescription does not expose the iOS 26
        // convenience constant. The app target itself is pinned to iOS 26;
        // this shared core only needs iOS 13 for its concurrency APIs.
        .iOS(.v13),
    ],
    products: [
        .library(name: "WhatsAppDomainCore", targets: ["WhatsAppDomainCore"]),
        .library(name: "WhatsAppBridgeCore", targets: ["WhatsAppBridgeCore"]),
        .library(name: "TranslationCore", targets: ["TranslationCore"]),
        .library(name: "PersistenceCore", targets: ["PersistenceCore"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"]),
            ]
        ),
        .target(
            name: "WhatsAppDomainCore",
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppRootView.swift",
                "SQLiteContextPersistence.swift",
                "SQLitePersistence.swift",
                "TranslationBenchmarkFixtures.swift",
                "QwenFunctionalTranslationFixtures.swift",
                "TranslationCore.swift",
                "TranslationEngineCore.swift",
                "WhatsAppBridge.js",
                "WhatsAppBridgeSupport.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebKitBridgeRuntime.swift",
                "WhatsAppWebProbeView.swift",
                "WhatsAppWebTransportCore.swift",
            ],
            sources: ["WhatsAppDomain.swift"]
        ),
        .target(
            name: "WhatsAppBridgeCore",
            dependencies: ["WhatsAppDomainCore"],
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppRootView.swift",
                "SQLiteContextPersistence.swift",
                "SQLitePersistence.swift",
                "TranslationBenchmarkFixtures.swift",
                "QwenFunctionalTranslationFixtures.swift",
                "WhatsAppBridge.js",
                "WhatsAppDomain.swift",
                "TranslationCore.swift",
                "TranslationEngineCore.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebKitBridgeRuntime.swift",
                "WhatsAppWebProbeView.swift",
            ],
            sources: [
                "WhatsAppBridgeSupport.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
                "WhatsAppWebTransportCore.swift",
            ]
        ),
        .target(
            name: "TranslationCore",
            dependencies: ["WhatsAppDomainCore"],
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppRootView.swift",
                "SQLiteContextPersistence.swift",
                "SQLitePersistence.swift",
                "WhatsAppBridge.js",
                "WhatsAppBridgeSupport.swift",
                "WhatsAppDomain.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebKitBridgeRuntime.swift",
                "WhatsAppWebProbeView.swift",
                "WhatsAppWebTransportCore.swift",
            ],
            sources: [
                "TranslationBenchmarkFixtures.swift",
                "QwenFunctionalTranslationFixtures.swift",
                "TranslationCore.swift",
                "TranslationEngineCore.swift",
            ]
        ),
        .target(
            name: "PersistenceCore",
            dependencies: ["WhatsAppDomainCore", "CSQLite"],
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppRootView.swift",
                "TranslationBenchmarkFixtures.swift",
                "QwenFunctionalTranslationFixtures.swift",
                "TranslationCore.swift",
                "TranslationEngineCore.swift",
                "WhatsAppBridge.js",
                "WhatsAppBridgeSupport.swift",
                "WhatsAppDomain.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebKitBridgeRuntime.swift",
                "WhatsAppWebProbeView.swift",
                "WhatsAppWebTransportCore.swift",
            ],
            sources: [
                "SQLiteContextPersistence.swift",
                "SQLitePersistence.swift",
            ]
        ),
        .testTarget(
            name: "WhatsAppDomainCoreTests",
            dependencies: ["WhatsAppDomainCore"],
            path: "WhatsAppDomainTests"
        ),
        .testTarget(
            name: "WhatsAppBridgeCoreTests",
            dependencies: ["WhatsAppBridgeCore", "WhatsAppDomainCore"],
            path: "WhatsAppTranslatorTests"
        ),
        .testTarget(
            name: "TranslationCoreTests",
            dependencies: ["TranslationCore", "WhatsAppDomainCore"],
            path: "TranslationCoreTests"
        ),
        .testTarget(
            name: "PersistenceCoreTests",
            dependencies: ["PersistenceCore", "WhatsAppDomainCore", "CSQLite"],
            path: "PersistenceCoreTests"
        ),
    ]
)
