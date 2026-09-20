import Foundation
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class ExperimentalTranslateGemmaTests: XCTestCase {
    func testProvisioningCheckFailsClosedUntilSnapshotIsComplete() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("translategemma-\(UUID().uuidString)", isDirectory: true)
        let model = root.appendingPathComponent("model", isDirectory: true)
        let manifest = root.appendingPathComponent("input.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = ExperimentalTranslateGemma(directory: model, manifestURL: manifest)
        let initiallyProvisioned = await runtime.isProvisioned()
        XCTAssertFalse(initiallyProvisioned)

        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: manifest)
        let partiallyProvisioned = await runtime.isProvisioned()
        XCTAssertFalse(partiallyProvisioned)

        for name in ["config.json", "tokenizer.json", "model.safetensors"] {
            try Data().write(to: model.appendingPathComponent(name))
        }
        let fullyProvisioned = await runtime.isProvisioned()
        XCTAssertTrue(fullyProvisioned)
    }
}
