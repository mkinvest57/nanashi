import XCTest
@testable import Strand

/// Pins each provider client's pure model-list parser. Each provider returns a differently-shaped
/// "list models" body; the parser unwraps the right envelope, strips Gemini's "models/" id prefix,
/// and applies the per-provider relevance filter (chat-capable gemini-* only). Pure logic — no
/// network — so the wire-shape contracts stay covered without hitting a live API.
final class AIProviderModelListTests: XCTestCase {

    // MARK: - Gemini

    func testGeminiStripsModelsPrefixAndKeepsChatModels() {
        // Real shape: {"models":[{"name":"models/gemini-..."}]}. Non-chat ids (embeddings, AQA)
        // and non-gemini ids must be filtered out; the "models/" prefix must be stripped.
        let body: [String: Any] = [
            "models": [
                ["name": "models/gemini-2.5-pro"],
                ["name": "models/gemini-2.5-flash"],
                ["name": "models/gemini-embedding-001"],   // embeddings — drop
                ["name": "models/aqa"],                     // AQA — drop
                ["name": "models/text-embedding-004"],      // not gemini-* — drop
                ["name": "models/imagen-3.0-generate-002"]  // not gemini-* — drop
            ]
        ]
        let ids = GeminiClient().parseModels(body)
        XCTAssertEqual(ids, ["gemini-2.5-pro", "gemini-2.5-flash"])
    }

    func testGeminiToleratesNameWithoutModelsPrefix() {
        // Defensive: an id that already lacks the "models/" prefix is still accepted as-is.
        let body: [String: Any] = ["models": [["name": "gemini-2.0-flash"]]]
        XCTAssertEqual(GeminiClient().parseModels(body), ["gemini-2.0-flash"])
    }

    func testGeminiDropsEmptyAndMalformedRows() {
        let body: [String: Any] = [
            "models": [
                ["name": ""],                 // empty — drop
                ["id": "gemini-2.5-flash"],   // wrong key for gemini — drop
                ["name": "models/gemini-2.5-flash-lite"]
            ]
        ]
        XCTAssertEqual(GeminiClient().parseModels(body), ["gemini-2.5-flash-lite"])
    }

    func testGeminiWrongEnvelopeKeyYieldsEmpty() {
        // Gemini reads "models", not "data" — an OpenAI-shaped body must parse to nothing.
        let body: [String: Any] = ["data": [["id": "gemini-2.5-flash"]]]
        XCTAssertTrue(GeminiClient().parseModels(body).isEmpty)
    }

    func testGeminiUsesEndpointCapabilitiesAndRejectsSpecializedGeneration() {
        let body: [String: Any] = ["models": [
            ["name": "models/gemini-4-argon", "supportedGenerationMethods": ["generateContent", "countTokens"]],
            ["name": "models/gemini-future-text", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["countTokens"]],
            ["name": "models/gemini-3.8-live", "supportedGenerationMethods": ["bidiGenerateContent"]],
            ["name": "models/gemini-3.8-flash-tts", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-nano-banana-2.1", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-3-pro-image", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-3.5-transcribe", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-omni-1.1-flash", "supportedGenerationMethods": ["generateContent"]]
        ]]
        XCTAssertEqual(GeminiClient().parseModels(body), ["gemini-4-argon", "gemini-future-text"])
    }

    func testCurrentReasoningAndTextModelsAreNotHiddenByCatalogueFilter() {
        let ids = ["gpt-6-luna", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-astra"]
        XCTAssertEqual(OpenAIClient().parseModels(["data": (ids + ["gpt-live", "gpt-live-mini"]).map { ["id": $0] }]), ids)
        for provider in [AIProvider.openAI, .anthropic, .gemini] {
            XCTAssertTrue(provider.modelOptions.contains(provider.defaultModel))
        }
    }

    func testOpenAIExcludesModelsWhoseAnnouncedShutdownDateHasPassed() {
        let now = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")!
        let body: [String: Any] = ["data": [
            ["id": "gpt-old-retired", "shutdown_date": "2026-10-26"],
            ["id": "gpt-retired-today", "shutdown_date": "2026-10-27"],
            ["id": "gpt-still-available", "shutdown_date": "2026-10-28"],
            ["id": "gpt-no-retirement-date"],
            ["id": "gpt-unknown-date", "shutdown_date": "unknown"]
        ]]
        XCTAssertEqual(OpenAIClient().parseModels(body, now: now),
                       ["gpt-still-available", "gpt-no-retirement-date", "gpt-unknown-date"])
    }

    // MARK: - existing providers unchanged

    func testOpenAIFiltersToGptAndOFamilies() {
        let body: [String: Any] = [
            "data": [
                ["id": "gpt-4o"],
                ["id": "o3-mini"],
                ["id": "text-embedding-3-large"], // not gpt/o — drop
                ["id": ""]                         // empty — drop
            ]
        ]
        XCTAssertEqual(OpenAIClient().parseModels(body), ["gpt-4o", "o3-mini"])
    }

    func testOpenAICatalogExcludesKnownSpecializedAndResponsesOnlyModels() {
        let ids = ["gpt-5", "gpt-5-mini", "gpt-5.4", "gpt-5.5", "gpt-4.1-2025-04-14", "o3", "o4-mini",
                   "gpt-5-pro", "gpt-5-pro-2025-10-06", "gpt-5.2-pro", "gpt-5.4-pro", "gpt-5.5-pro",
                   "o1-pro", "o3-pro", "gpt-5-codex", "o3-deep-research", "gpt-realtime",
                   "gpt-4o-audio-preview", "gpt-image-1", "gpt-4o-transcribe", "gpt-4o-mini-tts", "other-model"]
        XCTAssertEqual(OpenAIClient().parseModels(["data": ids.map { ["id": $0] }]),
                       Array(ids.prefix(7)))
        // Custom servers own their model names and capabilities; the OpenAI catalog filter is not applied.
        XCTAssertEqual(CustomClient().parseModels(["data": [["id": "gpt-5-pro"]]]), ["gpt-5-pro"])
    }

    func testAnthropicKeepsAllNonEmptyIds() {
        let body: [String: Any] = [
            "data": [
                ["id": "claude-sonnet-4-6"],
                ["id": "claude-opus-4-8"],
                ["id": ""] // empty — drop
            ]
        ]
        XCTAssertEqual(AnthropicClient().parseModels(body), ["claude-sonnet-4-6", "claude-opus-4-8"])
    }

    func testAnthropicExcludesRetiredButKeepsAvailableDeprecatedModels() {
        let body: [String: Any] = ["data": [
            ["id": "claude-sonnet-5-5", "lifecycle": "active"],
            ["id": "older-but-available", "lifecycle": "deprecated"],
            ["id": "retired-model", "lifecycle": "retired"]
        ]]
        XCTAssertEqual(AnthropicClient().parseModels(body), ["claude-sonnet-5-5", "older-but-available"])
    }

    func testAnthropicReasoningBlocksDoNotHideOrLeakIntoVisibleAnswer() throws {
        let body: [String: Any] = ["content": [
            ["type": "thinking", "thinking": "Private reasoning", "text": "Not a visible block"],
            ["type": "text", "text": "A clear "],
            ["type": "tool_use", "name": "example", "text": "Not visible either"],
            ["type": "text", "text": "answer."]
        ]]
        XCTAssertEqual(try AnthropicClient().parseTextReply(body), "A clear answer.")
        XCTAssertThrowsError(try AnthropicClient().parseTextReply(["content": [["type": "thinking", "thinking": "No answer"]]]))
    }

    // MARK: - Custom (OpenAI-compatible / local LLM)

    func testCustomKeepsAllNonEmptyIdsUnfiltered() {
        // A local server (Ollama / LM Studio) names models freely — none start with gpt/o, so unlike
        // OpenAI the Custom parser must keep them all (dropping only empties).
        let body: [String: Any] = [
            "data": [
                ["id": "llama3.1:8b"],
                ["id": "qwen2.5-coder"],
                ["id": "phi4"],
                ["id": ""] // empty — drop
            ]
        ]
        XCTAssertEqual(CustomClient().parseModels(body),
                       ["llama3.1:8b", "qwen2.5-coder", "phi4"])
    }

    func testCustomWrongEnvelopeKeyYieldsEmpty() {
        // Custom reads the OpenAI "data" envelope — a Gemini-shaped body parses to nothing.
        let body: [String: Any] = ["models": [["name": "models/llama3.1"]]]
        XCTAssertTrue(CustomClient().parseModels(body).isEmpty)
    }

    func testCustomKeepsGatewayCatalogModels() {
        let body: [String: Any] = [
            "service": "Gateway",
            "catalog": [
                ["tool": "OpenAI", "models": ["gpt-5", "gpt-5.5"]],
                ["tool": "Other", "models": ["claude-sonnet-4-6@default", "gpt-5"]]
            ]
        ]
        XCTAssertEqual(CustomClient().parseModels(body),
                       ["gpt-5", "gpt-5.5", "claude-sonnet-4-6@default"])
    }
}
