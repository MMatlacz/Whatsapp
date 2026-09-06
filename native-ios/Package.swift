// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhatsAppBridgeCore",
    products: [
        .library(name: "WhatsAppBridgeCore", targets: ["WhatsAppBridgeCore"]),
    ],
    targets: [
        .target(
            name: "WhatsAppBridgeCore",
            path: "WhatsAppTranslator",
            sources: ["WhatsAppBridgeSupport.swift"]
        ),
        .testTarget(
            name: "WhatsAppBridgeCoreTests",
            dependencies: ["WhatsAppBridgeCore"],
            path: "WhatsAppTranslatorTests"
        ),
    ]
)
