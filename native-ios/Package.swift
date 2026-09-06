// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatsAppTranslatorCore",
    products: [
        .library(name: "WhatsAppBridgeCore", targets: ["WhatsAppBridgeCore"]),
        .library(name: "TranslationCore", targets: ["TranslationCore"]),
    ],
    targets: [
        .target(
            name: "WhatsAppBridgeCore",
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "TranslationCore.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebProbeView.swift",
            ],
            sources: ["WhatsAppBridgeSupport.swift"]
        ),
        .target(
            name: "TranslationCore",
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppBridgeSupport.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebProbeView.swift",
            ],
            sources: ["TranslationCore.swift"]
        ),
        .testTarget(
            name: "WhatsAppBridgeCoreTests",
            dependencies: ["WhatsAppBridgeCore"],
            path: "WhatsAppTranslatorTests"
        ),
        .testTarget(
            name: "TranslationCoreTests",
            dependencies: ["TranslationCore"],
            path: "TranslationCoreTests"
        ),
    ]
)
