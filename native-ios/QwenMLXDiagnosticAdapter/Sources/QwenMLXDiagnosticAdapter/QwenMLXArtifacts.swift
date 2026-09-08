import CryptoKit
import Foundation

public struct QwenMLXArtifactManifest: Equatable, Sendable {
    public struct Artifact: Equatable, Sendable {
        public let path: String
        public let exactByteCount: Int64?
        public let sha256: String?

        init(
            path: String,
            exactByteCount: Int64? = nil,
            sha256: String? = nil
        ) {
            self.path = path
            self.exactByteCount = exactByteCount
            self.sha256 = sha256
        }
    }

    public let repositoryID: String
    public let revision: String
    public let tokenizerRevision: String
    public let chatTemplateRevision: String
    public let quantization: String
    public let artifacts: [Artifact]

    init(
        repositoryID: String,
        revision: String,
        tokenizerRevision: String,
        chatTemplateRevision: String,
        quantization: String,
        artifacts: [Artifact]
    ) {
        self.repositoryID = repositoryID
        self.revision = revision
        self.tokenizerRevision = tokenizerRevision
        self.chatTemplateRevision = chatTemplateRevision
        self.quantization = quantization
        self.artifacts = artifacts
    }

    public static let qwen3_0_6B_4Bit = QwenMLXArtifactManifest(
        repositoryID: "mlx-community/Qwen3-0.6B-4bit",
        revision: "73e3e38d981303bc594367cd910ea6eb48349da8",
        tokenizerRevision: "73e3e38d981303bc594367cd910ea6eb48349da8",
        chatTemplateRevision: "73e3e38d981303bc594367cd910ea6eb48349da8",
        quantization: "4-bit, group_size=64",
        artifacts: [
            Artifact(path: "added_tokens.json"),
            Artifact(path: "config.json"),
            Artifact(path: "merges.txt"),
            Artifact(
                path: "model.safetensors",
                exactByteCount: 335_450_584,
                sha256: "392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2"
            ),
            Artifact(path: "model.safetensors.index.json"),
            Artifact(path: "special_tokens_map.json"),
            Artifact(path: "tokenizer.json"),
            Artifact(path: "tokenizer_config.json"),
            Artifact(path: "vocab.json"),
        ]
    )
}

public enum QwenMLXArtifactVerificationError: Error, Equatable, Sendable {
    case directoryMissing(String)
    case missingFile(String)
    case unexpectedFileSize(path: String, expected: Int64, actual: Int64)
    case checksumMismatch(path: String, expected: String, actual: String)
}

extension QwenMLXArtifactVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .directoryMissing(let path):
            "Qwen MLX artifact directory is missing: \(path)"
        case .missingFile(let path):
            "Qwen MLX artifact is missing: \(path)"
        case .unexpectedFileSize(let path, let expected, let actual):
            "Qwen MLX artifact \(path) has \(actual) bytes; expected \(expected)."
        case .checksumMismatch(let path, let expected, let actual):
            "Qwen MLX artifact \(path) has SHA-256 \(actual); expected \(expected)."
        }
    }
}

public struct QwenMLXVerifiedArtifacts: Sendable {
    public let directory: URL
    public let manifest: QwenMLXArtifactManifest

    fileprivate init(
        directory: URL,
        manifest: QwenMLXArtifactManifest
    ) {
        self.directory = directory.standardizedFileURL
        self.manifest = manifest
    }

    func requiredFilesArePresent(
        fileManager: FileManager = .default
    ) -> Bool {
        manifest.artifacts.allSatisfy { artifact in
            let url = directory.appendingPathComponent(artifact.path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                return false
            }

            if let expected = artifact.exactByteCount {
                guard
                    let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                    let actual = (attributes[.size] as? NSNumber)?.int64Value,
                    actual == expected
                else {
                    return false
                }
            }

            return true
        }
    }
}

public enum QwenMLXArtifactVerifier {
    public static func verify(
        directory: URL,
        manifest: QwenMLXArtifactManifest = .qwen3_0_6B_4Bit,
        fileManager: FileManager = .default
    ) throws -> QwenMLXVerifiedArtifacts {
        let directory = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw QwenMLXArtifactVerificationError.directoryMissing(
                directory.path
            )
        }

        for artifact in manifest.artifacts {
            let url = directory.appendingPathComponent(artifact.path)
            var artifactIsDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: url.path,
                isDirectory: &artifactIsDirectory
            ), !artifactIsDirectory.boolValue else {
                throw QwenMLXArtifactVerificationError.missingFile(
                    artifact.path
                )
            }

            if let expected = artifact.exactByteCount {
                let attributes = try fileManager.attributesOfItem(
                    atPath: url.path
                )
                let actual = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                guard actual == expected else {
                    throw QwenMLXArtifactVerificationError.unexpectedFileSize(
                        path: artifact.path,
                        expected: expected,
                        actual: actual
                    )
                }
            }

            if let expected = artifact.sha256 {
                let actual = try sha256(of: url)
                guard actual == expected.lowercased() else {
                    throw QwenMLXArtifactVerificationError.checksumMismatch(
                        path: artifact.path,
                        expected: expected.lowercased(),
                        actual: actual
                    )
                }
            }
        }

        return QwenMLXVerifiedArtifacts(
            directory: directory,
            manifest: manifest
        )
    }

    private static func sha256(
        of url: URL,
        chunkSize: Int = 1_048_576
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
