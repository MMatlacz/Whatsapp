import Testing
@testable import QwenMLXHarness

struct HarnessValidationTests {
    @Test
    func defaultTemperatureIsFloatZero() throws {
        // A Double regression must fail compilation, not just numeric equality.
        let temperature: Float = try HarnessOptions.parse([]).temperature
        #expect(temperature == 0)
    }

    @Test(arguments: ["0", "0.7", "1", "3.4028235e38"])
    func acceptsFiniteNonnegativeTemperature(_ rawValue: String) throws {
        let options = try HarnessOptions.parse(["--temperature", rawValue])
        let temperature: Float = options.temperature
        #expect(temperature == Float(rawValue))
        #expect(temperature.isFinite)
    }

    @Test(arguments: ["-0.01", "nan", "inf", "-inf", "infinity", "1e100", "invalid", ""])
    func rejectsInvalidTemperature(_ rawValue: String) {
        #expect(throws: HarnessError.invalidValue("--temperature", rawValue)) {
            try HarnessOptions.parse(["--temperature", rawValue])
        }
    }

    @Test
    func rejectsMissingTemperature() {
        #expect(throws: HarnessError.missingValue("--temperature")) {
            try HarnessOptions.parse(["--temperature"])
        }
    }

    @Test
    func preservesOtherOptions() throws {
        let options = try HarnessOptions.parse([
            "--model", "example/model",
            "--prompt", "Reply with OK.",
            "--system", "Be concise.",
            "--max-tokens", "16",
            "--temperature", "0.5",
        ])
        #expect(options.modelID == "example/model")
        #expect(options.prompt == "Reply with OK.")
        #expect(options.systemPrompt == "Be concise.")
        #expect(options.maxTokens == 16)
    }

    @Test(arguments: [
        [String](),
        [""],
        [" ", "\t", "\r\n"],
        ["\u{00A0}", "\u{2003}", "\u{2028}"],
    ])
    func rejectsStreamsWithoutText(_ chunks: [String]) {
        var validator = ResponseValidator()
        for chunk in chunks {
            validator.observe(chunk)
        }
        #expect(throws: HarnessError.emptyResponse) {
            try validator.validate()
        }
    }

    @Test(arguments: [
        ["OK"],
        ["", " ", "O", "K", "\n", ""],
        ["\t", "Cześć", " 👋", "\n"],
    ])
    func acceptsStreamsContainingText(_ chunks: [String]) throws {
        var validator = ResponseValidator()
        for chunk in chunks {
            validator.observe(chunk)
        }
        try validator.validate()
    }

    @Test
    func emptyResponseHasActionableDiagnostic() {
        #expect(HarnessError.emptyResponse.description == "Model generated no non-whitespace text.")
    }
}
