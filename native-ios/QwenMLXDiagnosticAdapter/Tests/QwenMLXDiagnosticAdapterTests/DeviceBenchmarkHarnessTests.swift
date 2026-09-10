import Foundation
import XCTest

@testable import QwenMLXDiagnosticAdapter

final class DeviceBenchmarkHarnessTests: XCTestCase {
    func testHarnessStateRequiresVerifiedModelBeforeRun() {
        var state = QwenDeviceBenchmarkHarnessState()

        XCTAssertFalse(state.beginRun())
        XCTAssertEqual(state.phase, .failed)
        XCTAssertFalse(state.exportAvailable)
    }

    func testHarnessStateSupportsVerificationRunCancellationAndColdReset() {
        var state = QwenDeviceBenchmarkHarnessState()
        let directory = URL(fileURLWithPath: "/tmp/qwen-model", isDirectory: true)

        state.beginVerification()
        XCTAssertEqual(state.phase, .verifying)

        state.verificationSucceeded(directory: directory)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.modelDirectoryPath, directory.standardizedFileURL.path)

        XCTAssertTrue(state.beginRun())
        XCTAssertEqual(state.phase, .running)

        state.requestCancellation()
        XCTAssertEqual(state.phase, .cancelling)

        state.runCompleted(exportAvailable: true)
        XCTAssertEqual(state.phase, .completed)
        XCTAssertTrue(state.exportAvailable)

        state.resetForColdRun()
        XCTAssertEqual(state.phase, .ready)
        XCTAssertFalse(state.exportAvailable)
        XCTAssertTrue(state.statusMessage.contains("cold"))
    }

    func testBenchmarkSessionRejectsInvalidTimeoutBeforeInference() async throws {
        let fixture = try makeArtifactFixture()
        defer { fixture.cleanup() }
        let verified = try QwenMLXArtifactVerifier.verify(
            directory: fixture.directory,
            manifest: fixture.manifest
        )
        let session = QwenMLXBenchmarkSession(verifiedArtifacts: verified)

        do {
            _ = try await session.runSharedP01(
                timestamp: "2026-09-09T18:00:00Z",
                sourceRevision: "fixture",
                timeoutSeconds: 0
            )
            XCTFail("Expected invalid timeout")
        } catch let error as QwenMLXBenchmarkSessionError {
            XCTAssertEqual(error, .invalidTimeout)
        }
    }

    private func makeArtifactFixture() throws -> ArtifactFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(#"{"model_type":"qwen3"}"#.utf8).write(
            to: directory.appendingPathComponent("config.json")
        )
        try Data("weights".utf8).write(
            to: directory.appendingPathComponent("model.safetensors")
        )

        let manifest = QwenMLXArtifactManifest(
            repositoryID: "fixture/model",
            revision: "fixture-revision",
            tokenizerRevision: "fixture-revision",
            chatTemplateRevision: "fixture-revision",
            quantization: "fixture",
            artifacts: [
                .init(path: "config.json"),
                .init(
                    path: "model.safetensors",
                    exactByteCount: 7,
                    sha256: "9a129038d9a00aed0cf6a7ea059ca50a813449061ab87848cf1a13eafdf33b2c"
                ),
            ]
        )
        return ArtifactFixture(directory: directory, manifest: manifest)
    }
}

private struct ArtifactFixture {
    let directory: URL
    let manifest: QwenMLXArtifactManifest

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
