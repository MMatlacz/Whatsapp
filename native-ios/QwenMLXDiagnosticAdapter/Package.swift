// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QwenMLXDiagnosticAdapter",
    platforms: [
        .macOS(.v14),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "QwenMLXDiagnosticAdapter",
            targets: ["QwenMLXDiagnosticAdapter"]
        ),
        .executable(
            name: "qwen-mlx-benchmark",
            targets: ["QwenMLXBenchmark"]
        ),
    ],
    dependencies: [
        .package(name: "WhatsAppTranslatorCore", path: ".."),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            exact: "3.31.3"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            exact: "1.3.4"
        ),
    ],
    targets: [
        .target(
            name: "QwenMLXDiagnosticAdapter",
            dependencies: [
                .product(
                    name: "TranslationCore",
                    package: "WhatsAppTranslatorCore"
                ),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .executableTarget(
            name: "QwenMLXBenchmark",
            dependencies: [
                "QwenMLXDiagnosticAdapter",
                .product(
                    name: "TranslationCore",
                    package: "WhatsAppTranslatorCore"
                ),
            ]
        ),
        .testTarget(
            name: "QwenMLXDiagnosticAdapterTests",
            dependencies: [
                "QwenMLXDiagnosticAdapter",
                .product(
                    name: "TranslationCore",
                    package: "WhatsAppTranslatorCore"
                ),
            ]
        ),
    ]
)
