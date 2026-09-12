import Foundation
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class TranslationTokenProbeTests: XCTestCase {
    func testRejectsMissingArtifactManifestBeforeLoadingModel() async throws {
        try await expectFailure(artifacts: [], tokens: [2, 10], expected: .invalidInput)
    }

    func testRejectsOutOfVocabularyTokenBeforeLoadingModel() async throws {
        try await expectFailure(artifacts: manifest, tokens: [-1], expected: .invalidInput)
    }

    func testRejectsTamperedArtifactBeforeLoadingModel() async throws {
        try await expectFailure(artifacts: manifest, tokens: [2, 10], expected: .integrityFailure)
    }

    private var manifest: [[String: Any]] {
        ["config.json", "tokenizer.json", "model.safetensors"].map {
            ["path": $0, "bytes": 1, "sha256": String(repeating: "0", count: 64)]
        }
    }

    private func expectFailure(
        artifacts: [[String: Any]], tokens: [Int], expected: TranslationTokenProbe.ProbeError
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("x".utf8).write(to: root.appendingPathComponent("config.json"))
        let input: [String: Any] = [
            "model": ["repository": "mlx-community/translategemma-4b-it-4bit",
                      "revision": "5788ec08c047f3f2e17808101b8d9566ac930d58",
                      "artifacts": artifacts],
            "results": [["fixtureID": "synthetic", "actualInput": "test", "inputTokenIDs": tokens]],
        ]
        let file = root.appendingPathComponent("input.json")
        try JSONSerialization.data(withJSONObject: input).write(to: file)
        do {
            try await TranslationTokenProbe.run(
                modelDirectory: root, inputFile: file,
                outputFile: root.appendingPathComponent("output.json"), sourceRevision: "test"
            )
            XCTFail("Invalid probe input was accepted")
        } catch {
            XCTAssertEqual(error as? TranslationTokenProbe.ProbeError, expected)
        }
    }
}
