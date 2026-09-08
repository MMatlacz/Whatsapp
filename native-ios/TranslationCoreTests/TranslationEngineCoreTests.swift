import XCTest
@testable import TranslationCore

final class TranslationEngineCoreTests: XCTestCase {
    func testValidatedRequestAndModelMetadataRejectInvalidValues() throws {
        XCTAssertNil(TranslationRequestID(rawValue: "   "))
        XCTAssertNil(TranslationLanguagePair(sourceLanguage: "", targetLanguage: "pl"))
        XCTAssertNil(TranslationLanguagePair(sourceLanguage: "id", targetLanguage: "   "))
        XCTAssertNil(TranslationModelDescriptor(identifier: "", version: "1"))
        XCTAssertNil(TranslationModelDescriptor(identifier: "model", version: "  "))

        let prompt = try makePrompt()
        let requestID = try XCTUnwrap(TranslationRequestID(rawValue: "request-1"))
        let languages = try XCTUnwrap(
            TranslationLanguagePair(sourceLanguage: " id ", targetLanguage: " pl ")
        )

        XCTAssertEqual(languages.sourceLanguage, "id")
        XCTAssertEqual(languages.targetLanguage, "pl")
        XCTAssertNil(
            TranslationRequest(
                id: requestID,
                revision: 0,
                languages: languages,
                prompt: prompt
            )
        )
        XCTAssertNotNil(
            TranslationRequest(
                id: requestID,
                revision: 1,
                languages: languages,
                prompt: prompt
            )
        )
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
        let primaryRequests = await primaryRecorder.requests()
        let fallbackRequests = await fallbackRecorder.requests()

        XCTAssertEqual(result.requestID, request.id)
        XCTAssertEqual(result.revision, 3)
        XCTAssertEqual(result.promptVersion, request.prompt.version)
        XCTAssertEqual(result.model, primary.model)
        XCTAssertEqual(result.translatedText, "Tłumaczenie")
        XCTAssertEqual(primaryRequests, [request])
        XCTAssertTrue(fallbackRequests.isEmpty)
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
        let primaryRequests = await primaryRecorder.requests()
        let fallbackRequests = await fallbackRecorder.requests()

        XCTAssertEqual(result.model, fallback.model)
        XCTAssertTrue(primaryRequests.isEmpty)
        XCTAssertEqual(fallbackRequests, [request])
    }

    func testRetryableExecutionFailuresFallBackWithSameRequest() async throws {
        for failure in [
            TranslationEngineFailure.unavailable,
            .transient,
            .unsupported,
        ] {
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
            let primaryRequests = await primaryRecorder.requests()
            let fallbackRequests = await fallbackRecorder.requests()

            XCTAssertEqual(result.model, fallback.model)
            XCTAssertEqual(primaryRequests, [request])
            XCTAssertEqual(fallbackRequests, [request])
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

            let fallbackRequests = await fallbackRecorder.requests()
            XCTAssertTrue(fallbackRequests.isEmpty)
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

        let fallbackRequests = await fallbackRecorder.requests()
        XCTAssertTrue(fallbackRequests.isEmpty)
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

        let fallbackRequests = await fallbackRecorder.requests()
        XCTAssertTrue(fallbackRequests.isEmpty)
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

        let fallbackRequests = await fallbackRecorder.requests()
        XCTAssertTrue(fallbackRequests.isEmpty)
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

    func testTwoStepProviderUsesEnglishIntermediateAndPreservesStageOrder() async throws {
        let firstRecorder = ProviderRecorder()
        let secondRecorder = ProviderRecorder()
        let first = ScriptedTextProvider(
            identifier: "provider-id-en",
            output: .success("She will come later."),
            recorder: firstRecorder
        )
        let second = ScriptedTextProvider(
            identifier: "provider-en-pl",
            output: .success("Ona przyjdzie później."),
            recorder: secondRecorder
        )
        let pipeline = try XCTUnwrap(
            TwoStepTranslationProvider(
                intermediateLanguage: "en",
                sourceToIntermediate: first,
                intermediateToTarget: second
            )
        )

        let availability = await pipeline.availability(
            sourceLanguage: "id",
            targetLanguage: "pl"
        )
        XCTAssertEqual(availability, .available)
        let output = try await pipeline.translate(
            text: "Dia nanti nyusul.",
            sourceLanguage: "id",
            targetLanguage: "pl"
        )

        XCTAssertEqual(output, "Ona przyjdzie później.")
        let firstEvents = await firstRecorder.events()
        XCTAssertEqual(
            firstEvents,
            [
                .availability(sourceLanguage: "id", targetLanguage: "en"),
                .translate(
                    text: "Dia nanti nyusul.",
                    sourceLanguage: "id",
                    targetLanguage: "en"
                ),
            ]
        )
        let secondEvents = await secondRecorder.events()
        XCTAssertEqual(
            secondEvents,
            [
                .availability(sourceLanguage: "en", targetLanguage: "pl"),
                .translate(
                    text: "She will come later.",
                    sourceLanguage: "en",
                    targetLanguage: "pl"
                ),
            ]
        )
    }

    func testTwoStepProviderStopsAvailabilityAtUnavailableFirstHop() async throws {
        let firstRecorder = ProviderRecorder()
        let secondRecorder = ProviderRecorder()
        let first = ScriptedTextProvider(
            identifier: "provider-id-en",
            availabilityValue: .unavailable(.unsupportedLanguagePair),
            output: .success("unused"),
            recorder: firstRecorder
        )
        let second = ScriptedTextProvider(
            identifier: "provider-en-pl",
            output: .success("unused"),
            recorder: secondRecorder
        )
        let pipeline = try XCTUnwrap(
            TwoStepTranslationProvider(
                intermediateLanguage: "en",
                sourceToIntermediate: first,
                intermediateToTarget: second
            )
        )

        let availability = await pipeline.availability(
            sourceLanguage: "id",
            targetLanguage: "pl"
        )
        XCTAssertEqual(availability, .unavailable(.unsupportedLanguagePair))
        let firstEvents = await firstRecorder.events()
        XCTAssertEqual(
            firstEvents,
            [.availability(sourceLanguage: "id", targetLanguage: "en")]
        )
        let secondEvents = await secondRecorder.events()
        XCTAssertTrue(secondEvents.isEmpty)
    }

    func testTwoStepProviderPropagatesFirstHopFailureWithoutCallingSecondHop() async throws {
        let firstRecorder = ProviderRecorder()
        let secondRecorder = ProviderRecorder()
        let first = ScriptedTextProvider(
            identifier: "provider-id-en",
            output: .failure(.unsupported),
            recorder: firstRecorder
        )
        let second = ScriptedTextProvider(
            identifier: "provider-en-pl",
            output: .success("unused"),
            recorder: secondRecorder
        )
        let pipeline = try XCTUnwrap(
            TwoStepTranslationProvider(
                sourceToIntermediate: first,
                intermediateToTarget: second
            )
        )

        do {
            _ = try await pipeline.translate(
                text: "Dia nanti nyusul.",
                sourceLanguage: "id",
                targetLanguage: "pl"
            )
            XCTFail("Expected the first hop failure")
        } catch let error as TranslationEngineFailure {
            XCTAssertEqual(error, .unsupported)
        }

        let firstEvents = await firstRecorder.events()
        XCTAssertEqual(
            firstEvents,
            [
                .translate(
                    text: "Dia nanti nyusul.",
                    sourceLanguage: "id",
                    targetLanguage: "en"
                ),
            ]
        )
        let secondEvents = await secondRecorder.events()
        XCTAssertTrue(secondEvents.isEmpty)
    }

    func testTwoStepProviderRejectsEmptyIntermediateOutput() async throws {
        let secondRecorder = ProviderRecorder()
        let first = ScriptedTextProvider(
            identifier: "provider-id-en",
            output: .success("   ")
        )
        let second = ScriptedTextProvider(
            identifier: "provider-en-pl",
            output: .success("unused"),
            recorder: secondRecorder
        )
        let pipeline = try XCTUnwrap(
            TwoStepTranslationProvider(
                sourceToIntermediate: first,
                intermediateToTarget: second
            )
        )

        do {
            _ = try await pipeline.translate(
                text: "Dia nanti nyusul.",
                sourceLanguage: "id",
                targetLanguage: "pl"
            )
            XCTFail("Expected the empty intermediate result to fail closed")
        } catch let error as TranslationEngineFailure {
            XCTAssertEqual(error, .permanent)
        }

        let secondEvents = await secondRecorder.events()
        XCTAssertTrue(secondEvents.isEmpty)
    }

    func testUnavailableLocalModelFallsBackToTwoStepProvider() async throws {
        let localRecorder = ProviderRecorder()
        let firstRecorder = ProviderRecorder()
        let secondRecorder = ProviderRecorder()
        let localModel = ScriptedMultilingualModel(
            identifier: "multilingual-local-model",
            availabilityValue: .unavailable(.notInstalled),
            output: .success("unused"),
            recorder: localRecorder
        )
        let first = ScriptedTextProvider(
            identifier: "provider-id-en",
            output: .success("She will come later."),
            recorder: firstRecorder
        )
        let second = ScriptedTextProvider(
            identifier: "provider-en-pl",
            output: .success("Ona przyjdzie później."),
            recorder: secondRecorder
        )
        let pipeline = try XCTUnwrap(
            TwoStepTranslationProvider(
                sourceToIntermediate: first,
                intermediateToTarget: second
            )
        )
        let localEngine = try XCTUnwrap(
            LocalMultilingualModelEngine(
                localModel: localModel,
                model: try XCTUnwrap(
                    TranslationModelDescriptor(
                        identifier: "multilingual-local-model",
                        version: "experimental-v1"
                    )
                )
            )
        )
        let providerEngine = try XCTUnwrap(
            TwoStepTranslationEngine(
                provider: pipeline,
                model: try XCTUnwrap(
                    TranslationModelDescriptor(
                        identifier: "two-step-provider",
                        version: "experimental-v1"
                    )
                )
            )
        )
        let router = try TranslationEngineRouter(engines: [localEngine, providerEngine])

        let result = try await router.translate(try makeRequest())

        XCTAssertEqual(result.model, providerEngine.model)
        XCTAssertEqual(result.translatedText, "Ona przyjdzie później.")
        let localEvents = await localRecorder.events()
        XCTAssertEqual(
            localEvents,
            [.availability(sourceLanguage: "id", targetLanguage: "pl")]
        )
        let firstEvents = await firstRecorder.events()
        XCTAssertEqual(
            firstEvents,
            [
                .availability(sourceLanguage: "id", targetLanguage: "en"),
                .translate(
                    text: "Dia nanti nyusul.",
                    sourceLanguage: "id",
                    targetLanguage: "en"
                ),
            ]
        )
        let secondEvents = await secondRecorder.events()
        XCTAssertEqual(
            secondEvents,
            [
                .availability(sourceLanguage: "en", targetLanguage: "pl"),
                .translate(
                    text: "She will come later.",
                    sourceLanguage: "en",
                    targetLanguage: "pl"
                ),
            ]
        )
    }

    func testLocalMultilingualModelEnginePassesSourceTextAndProvenance() async throws {
        let recorder = ProviderRecorder()
        let localModel = ScriptedMultilingualModel(
            identifier: "multilingual-local-model",
            output: .success("Ona przyjdzie później."),
            recorder: recorder
        )
        let engine = try XCTUnwrap(
            LocalMultilingualModelEngine(
                localModel: localModel,
                version: "model-1"
            )
        )

        let request = try makeRequest(sourceText: "Dia nanti nyusul.")
        let result = try await engine.translate(request)

        XCTAssertEqual(result.model, engine.model)
        XCTAssertEqual(result.requestID, request.id)
        XCTAssertEqual(result.revision, request.revision)
        XCTAssertEqual(result.promptVersion, request.prompt.version)
        XCTAssertEqual(result.translatedText, "Ona przyjdzie później.")
        let events = await recorder.events()
        XCTAssertEqual(
            events,
            [
                .translate(
                    text: "Dia nanti nyusul.",
                    sourceLanguage: "id",
                    targetLanguage: "pl"
                ),
            ]
        )
    }

    func testProviderBackedEngineRejectsPromptOnlyRequestWithoutGuessingText() async throws {
        let recorder = ProviderRecorder()
        let localModel = ScriptedMultilingualModel(
            identifier: "multilingual-local-model",
            output: .success("unused"),
            recorder: recorder
        )
        let engine = try XCTUnwrap(
            LocalMultilingualModelEngine(
                localModel: localModel,
                version: "model-1"
            )
        )
        let requestID = try XCTUnwrap(TranslationRequestID(rawValue: "prompt-only"))
        let languages = try XCTUnwrap(
            TranslationLanguagePair(sourceLanguage: "id", targetLanguage: "pl")
        )
        let request = try XCTUnwrap(
            TranslationRequest(
                id: requestID,
                revision: 1,
                languages: languages,
                prompt: try makePrompt()
            )
        )

        do {
            _ = try await engine.translate(request)
            XCTFail("Expected source text to be required")
        } catch let error as TranslationEngineFailure {
            XCTAssertEqual(error, .invalidRequest)
        }
        let events = await recorder.events()
        XCTAssertTrue(events.isEmpty)
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

    private func makeRequest(
        revision: Int = 1,
        sourceText: String? = "Dia nanti nyusul."
    ) throws -> TranslationRequest {
        let requestID = try XCTUnwrap(
            TranslationRequestID(rawValue: "request-\(revision)")
        )
        let languages = try XCTUnwrap(
            TranslationLanguagePair(sourceLanguage: "id", targetLanguage: "pl")
        )
        return try XCTUnwrap(
            TranslationRequest(
                id: requestID,
                revision: revision,
                languages: languages,
                prompt: makePrompt(),
                sourceText: sourceText
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

private enum ScriptedTextOutcome: Sendable {
    case success(String)
    case failure(TranslationEngineFailure)
}

private enum ProviderEvent: Equatable, Sendable {
    case availability(sourceLanguage: String, targetLanguage: String)
    case translate(text: String, sourceLanguage: String, targetLanguage: String)
}

private actor ProviderRecorder {
    private var recordedEvents: [ProviderEvent] = []

    func record(_ event: ProviderEvent) {
        recordedEvents.append(event)
    }

    func events() -> [ProviderEvent] {
        recordedEvents
    }
}

private struct ScriptedTextProvider: TranslationTextProvider {
    let identifier: String
    let availabilityValue: TranslationEngineAvailability
    let output: ScriptedTextOutcome
    let recorder: ProviderRecorder

    init(
        identifier: String,
        availabilityValue: TranslationEngineAvailability = .available,
        output: ScriptedTextOutcome,
        recorder: ProviderRecorder = ProviderRecorder()
    ) {
        self.identifier = identifier
        self.availabilityValue = availabilityValue
        self.output = output
        self.recorder = recorder
    }

    func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        await recorder.record(
            .availability(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        )
        return availabilityValue
    }

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        await recorder.record(
            .translate(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        )
        switch output {
        case .success(let value):
            return value
        case .failure(let failure):
            throw failure
        }
    }
}

private struct ScriptedMultilingualModel: MultilingualLocalModel {
    let identifier: String
    let availabilityValue: TranslationEngineAvailability
    let output: ScriptedTextOutcome
    let recorder: ProviderRecorder

    init(
        identifier: String,
        availabilityValue: TranslationEngineAvailability = .available,
        output: ScriptedTextOutcome,
        recorder: ProviderRecorder = ProviderRecorder()
    ) {
        self.identifier = identifier
        self.availabilityValue = availabilityValue
        self.output = output
        self.recorder = recorder
    }

    func availability(
        sourceLanguage: String,
        targetLanguage: String
    ) async -> TranslationEngineAvailability {
        await recorder.record(
            .availability(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        )
        return availabilityValue
    }

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        await recorder.record(
            .translate(
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        )
        switch output {
        case .success(let value):
            return value
        case .failure(let failure):
            throw failure
        }
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
