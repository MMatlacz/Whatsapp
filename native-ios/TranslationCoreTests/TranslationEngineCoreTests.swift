import XCTest
@testable import TranslationCore

final class TranslationEngineCoreTests: XCTestCase {
    func testValidatedRequestAndModelMetadataRejectInvalidValues() throws {
        XCTAssertNil(TranslationRequestID(rawValue: "   "))
        XCTAssertNil(TranslationModelDescriptor(identifier: "", version: "1"))
        XCTAssertNil(TranslationModelDescriptor(identifier: "model", version: "  "))

        let prompt = try makePrompt()
        let requestID = try XCTUnwrap(TranslationRequestID(rawValue: "request-1"))

        XCTAssertNil(TranslationRequest(id: requestID, revision: 0, prompt: prompt))
        XCTAssertNotNil(TranslationRequest(id: requestID, revision: 1, prompt: prompt))
    }

    func testPrimarySuccessReturnsExactProvenanceWithoutCallingFallback() async throws {
        let request = try makeRequest(revision: 3)
        let primaryRecorder = EngineRecorder()
        let fallbackRecorder = EngineRecorder()
        let primary = try makeEngine(
            id: "primary",
            outcome: .success("Tłumaczenie"),
            recorder: primaryRecorder
        )
        let fallback = try makeEngine(
            id: "fallback",
            outcome: .success("Nie powinno się wykonać"),
            recorder: fallbackRecorder
        )
        let router = try TranslationEngineRouter(engines: [primary, fallback])

        let result = try await router.translate(request)

        XCTAssertEqual(result.requestID, request.id)
        XCTAssertEqual(result.revision, 3)
        XCTAssertEqual(result.promptVersion, request.prompt.version)
        XCTAssertEqual(result.model, primary.model)
        XCTAssertEqual(result.translatedText, "Tłumaczenie")
        XCTAssertEqual(await primaryRecorder.requests(), [request])
        XCTAssertTrue(await fallbackRecorder.requests().isEmpty)
    }

    func testUnavailablePrimaryFallsBackWithoutInvokingPrimaryTranslate() async throws {
        let request = try makeRequest()
        let primaryRecorder = EngineRecorder()
        let fallbackRecorder = EngineRecorder()
        let primary = try makeEngine(
            id: "primary",
            availability: .unavailable(.unsupportedLanguagePair),
            outcome: .success("unused"),
            recorder: primaryRecorder
        )
        let fallback = try makeEngine(
            id: "fallback",
            outcome: .success("Dobrze"),
            recorder: fallbackRecorder
        )
        let router = try TranslationEngineRouter(engines: [primary, fallback])

        let result = try await router.translate(request)

        XCTAssertEqual(result.model, fallback.model)
        XCTAssertTrue(await primaryRecorder.requests().isEmpty)
        XCTAssertEqual(await fallbackRecorder.requests(), [request])
    }

    func testTransientAndUnsupportedFailuresFallBackWithSameRequest() async throws {
        for failure in [TranslationEngineFailure.transient, .unsupported] {
            let request = try makeRequest(revision: 5)
            let primaryRecorder = EngineRecorder()
            let fallbackRecorder = EngineRecorder()
            let primary = try makeEngine(
                id: "primary-\(String(describing: failure))",
                outcome: .failure(failure),
                recorder: primaryRecorder
            )
            let fallback = try makeEngine(
                id: "fallback-\(String(describing: failure))",
                outcome: .success("wynik"),
                recorder: fallbackRecorder
            )
            let router = try TranslationEngineRouter(engines: [primary, fallback])

            let result = try await router.translate(request)

            XCTAssertEqual(result.model, fallback.model)
            XCTAssertEqual(await primaryRecorder.requests(), [request])
            XCTAssertEqual(await fallbackRecorder.requests(), [request])
        }
    }

    func testPermanentAndInvalidRequestFailuresNeverFallBack() async throws {
        for failure in [TranslationEngineFailure.permanent, .invalidRequest] {
            let request = try makeRequest()
            let fallbackRecorder = EngineRecorder()
            let primary = try makeEngine(
                id: "primary-\(String(describing: failure))",
                outcome: .failure(failure)
            )
            let fallback = try makeEngine(
                id: "fallback-\(String(describing: failure))",
                outcome: .success("unused"),
                recorder: fallbackRecorder
            )
            let router = try TranslationEngineRouter(engines: [primary, fallback])

            do {
                _ = try await router.translate(request)
                XCTFail("Expected terminal failure")
            } catch let error as TranslationRoutingError {
                XCTAssertEqual(
                    error,
                    .terminalFailure(model: primary.model, failure: failure)
                )
            }

            XCTAssertTrue(await fallbackRecorder.requests().isEmpty)
        }
    }

    func testEngineCancellationNeverFallsBack() async throws {
        let request = try makeRequest()
        let fallbackRecorder = EngineRecorder()
        let primary = try makeEngine(id: "primary", outcome: .failure(.cancelled))
        let fallback = try makeEngine(
            id: "fallback",
            outcome: .success("unused"),
            recorder: fallbackRecorder
        )
        let router = try TranslationEngineRouter(engines: [primary, fallback])

        do {
            _ = try await router.translate(request)
            XCTFail("Expected cancellation")
        } catch let error as TranslationRoutingError {
            XCTAssertEqual(error, .cancelled)
        }

        XCTAssertTrue(await fallbackRecorder.requests().isEmpty)
    }

    func testUnexpectedUntypedEngineErrorIsContractViolationAndDoesNotFallback() async throws {
        let request = try makeRequest()
        let fallbackRecorder = EngineRecorder()
        let primary = try makeEngine(id: "primary", outcome: .unexpectedError)
        let fallback = try makeEngine(
            id: "fallback",
            outcome: .success("unused"),
            recorder: fallbackRecorder
        )
        let router = try TranslationEngineRouter(engines: [primary, fallback])

        do {
            _ = try await router.translate(request)
            XCTFail("Expected contract violation")
        } catch let error as TranslationRoutingError {
            XCTAssertEqual(
                error,
                .contractViolation(
                    model: primary.model,
                    violation: .unexpectedErrorType
                )
            )
        }

        XCTAssertTrue(await fallbackRecorder.requests().isEmpty)
    }

    func testMismatchedResultMetadataFailsClosedWithoutFallback() async throws {
        let request = try makeRequest(revision: 7)
        let fallbackRecorder = EngineRecorder()
        let wrongModel = try XCTUnwrap(
            TranslationModelDescriptor(identifier: "wrong", version: "1")
        )
        let primary = try makeEngine(
            id: "primary",
            outcome: .successWithModel("wynik", wrongModel)
        )
        let fallback = try makeEngine(
            id: "fallback",
            outcome: .success("unused"),
            recorder: fallbackRecorder
        )
        let router = try TranslationEngineRouter(engines: [primary, fallback])

        do {
            _ = try await router.translate(request)
            XCTFail("Expected model provenance violation")
        } catch let error as TranslationRoutingError {
            XCTAssertEqual(
                error,
                .contractViolation(
                    model: primary.model,
                    violation: .mismatchedModelDescriptor
                )
            )
        }

        XCTAssertTrue(await fallbackRecorder.requests().isEmpty)
    }

    func testDuplicateModelDescriptorsAreRejected() throws {
        let descriptor = try XCTUnwrap(
            TranslationModelDescriptor(identifier: "same", version: "1")
        )
        let first = ScriptedEngine(model: descriptor, outcome: .success("one"))
        let second = ScriptedEngine(model: descriptor, outcome: .success("two"))

        XCTAssertThrowsError(try TranslationEngineRouter(engines: [first, second])) { error in
            XCTAssertEqual(
                error as? TranslationRoutingError,
                .duplicateModelDescriptor(descriptor)
            )
        }
    }

    func testExhaustedRoutingReportsFailuresInPreferenceOrder() async throws {
        let request = try makeRequest()
        let first = try makeEngine(
            id: "first",
            availability: .unavailable(.notInstalled),
            outcome: .success("unused")
        )
        let second = try makeEngine(id: "second", outcome: .failure(.transient))
        let router = try TranslationEngineRouter(engines: [first, second])

        do {
            _ = try await router.translate(request)
            XCTFail("Expected exhausted routing")
        } catch let error as TranslationRoutingError {
            XCTAssertEqual(
                error,
                .exhausted([
                    .unavailable(model: first.model, reason: .notInstalled),
                    .execution(model: second.model, failure: .transient),
                ])
            )
        }
    }

    private func makePrompt() throws -> TranslationPrompt {
        let context = TranslationContext(
            target: TranslationTarget(speaker: .unknown, body: "Dia nanti nyusul."),
            recentTurns: [
                TranslationContextTurn(
                    speaker: try XCTUnwrap(TranslationSpeakerAlias(rawValue: "P1")),
                    body: "Rina masih di kantor."
                ),
            ],
            quotedTurn: nil,
            summary: nil
        )
        return try TranslationPromptBuilder().build(
            sourceLanguage: "id",
            targetLanguage: "pl",
            context: context
        )
    }

    private func makeRequest(revision: Int = 1) throws -> TranslationRequest {
        try XCTUnwrap(
            TranslationRequest(
                id: XCTUnwrap(TranslationRequestID(rawValue: "request-\(revision)")),
                revision: revision,
                prompt: makePrompt()
            )
        )
    }

    private func makeEngine(
        id: String,
        availability: TranslationEngineAvailability = .available,
        outcome: ScriptedEngine.Outcome,
        recorder: EngineRecorder = EngineRecorder()
    ) throws -> ScriptedEngine {
        ScriptedEngine(
            model: try XCTUnwrap(
                TranslationModelDescriptor(identifier: id, version: "1")
            ),
            availabilityValue: availability,
            outcome: outcome,
            recorder: recorder
        )
    }
}

private actor EngineRecorder {
    private var recordedRequests: [TranslationRequest] = []

    func record(_ request: TranslationRequest) {
        recordedRequests.append(request)
    }

    func requests() -> [TranslationRequest] {
        recordedRequests
    }
}

private struct ScriptedEngine: TranslationEngine {
    enum Outcome: Sendable {
        case success(String)
        case successWithModel(String, TranslationModelDescriptor)
        case failure(TranslationEngineFailure)
        case unexpectedError
    }

    let model: TranslationModelDescriptor
    let availabilityValue: TranslationEngineAvailability
    let outcome: Outcome
    let recorder: EngineRecorder

    init(
        model: TranslationModelDescriptor,
        availabilityValue: TranslationEngineAvailability = .available,
        outcome: Outcome,
        recorder: EngineRecorder = EngineRecorder()
    ) {
        self.model = model
        self.availabilityValue = availabilityValue
        self.outcome = outcome
        self.recorder = recorder
    }

    func availability(for request: TranslationRequest) async -> TranslationEngineAvailability {
        availabilityValue
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        await recorder.record(request)

        switch outcome {
        case .success(let text):
            return try makeResult(text: text, model: model, request: request)
        case .successWithModel(let text, let resultModel):
            return try makeResult(text: text, model: resultModel, request: request)
        case .failure(let failure):
            throw failure
        case .unexpectedError:
            throw ScriptedEngineError.unexpected
        }
    }

    private func makeResult(
        text: String,
        model: TranslationModelDescriptor,
        request: TranslationRequest
    ) throws -> TranslationResult {
        guard let result = TranslationResult(
            requestID: request.id,
            revision: request.revision,
            translatedText: text,
            model: model,
            promptVersion: request.prompt.version
        ) else {
            throw ScriptedEngineError.invalidFixture
        }
        return result
    }
}

private enum ScriptedEngineError: Error {
    case invalidFixture
    case unexpected
}
