// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatsAppTranslatorCore",
    products: [
        .library(name: "WhatsAppDomainCore", targets: ["WhatsAppDomainCore"]),
        .library(name: "WhatsAppBridgeCore", targets: ["WhatsAppBridgeCore"]),
        .library(name: "TranslationCore", targets: ["TranslationCore"]),
    ],
    targets: [
        .target(
            name: "WhatsAppDomainCore",
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "TranslationCore.swift",
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
                "WhatsAppBridge.js",
                "WhatsAppDomain.swift",
                "TranslationCore.swift",
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
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
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
            sources: ["TranslationCore.swift"]
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
            dependencies: ["TranslationCore"],
            path: "TranslationCoreTests"
        ),
    ]
)
