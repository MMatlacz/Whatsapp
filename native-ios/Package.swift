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
                "WhatsAppBridgeSupport.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebProbeView.swift",
            ],
            sources: ["WhatsAppDomain.swift"]
        ),
        .target(
            name: "WhatsAppBridgeCore",
            dependencies: ["WhatsAppDomainCore"],
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppDomain.swift",
                "TranslationCore.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebProbeView.swift",
            ],
            sources: [
                "WhatsAppBridgeSupport.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
            ]
        ),
        .target(
            name: "TranslationCore",
            path: "WhatsAppTranslator",
            exclude: [
                "DiagnosticsView.swift",
                "WhatsAppBridgeSupport.swift",
                "WhatsAppDomain.swift",
                "WhatsAppTransportCore.swift",
                "WhatsAppTransportDomainMapper.swift",
                "WhatsAppTranslatorApp.swift",
                "WhatsAppWebProbeView.swift",
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
