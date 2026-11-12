package com.noop.ai

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Wire-policy parity with the Swift provider's HTTP/SSE regression tests; no network or credentials. */
class OpenAiChatContractTest {
    @Test fun modernParametersKeepTheSelectedModelAndOmitUnsupportedSampling() {
        val body = OpenAiChatContract.parameters(JSONObject().put("model", "gpt-5"), modern = true)
        assertEquals("gpt-5", body.getString("model"))
        assertEquals(4096, body.getInt("max_completion_tokens"))
        assertFalse(body.has("max_tokens"))
        assertFalse(body.has("temperature"))
    }

    @Test fun legacyServersKeepTheirOriginalParameters() {
        val body = OpenAiChatContract.parameters(JSONObject(), modern = false)
        assertEquals(4096, body.getInt("max_tokens"))
        assertEquals(0.6, body.getDouble("temperature"), 0.0)
        assertFalse(body.has("max_completion_tokens"))
    }

    @Test fun rejectedParameterPolicyMatchesCompiledSwiftOracle() {
        val cases = listOf(
            400 to "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead.",
            400 to "Unsupported value: 'temperature'; only the default is supported",
            400 to "Unsupported model", 429 to "Unsupported parameter: max_tokens",
            500 to "Unsupported parameter: temperature", 400 to "max_tokens exceeds context window",
            400 to "Unsupported parameter: max_completion_tokens", 400 to "unknown parameter max_tokens",
            400 to "temperature must be between 0 and 2", 400 to "MAX_TOKENS is not supported",
            400 to "temperature not allowed", 401 to "temperature not allowed"
        )
        // Verbatim stdout from swiftc -O OpenAIChatTransport + oracle/main.swift (2026-10-23).
        val expected = "1,1,0,0,0,0,0,1,0,1,1,0"
        assertEquals(expected, cases.joinToString(",") {
            if (OpenAiChatContract.shouldRetryModernParams(it.first, it.second)) "1" else "0"
        })
    }

    @Test fun catalogCandidatesMatchCompiledSwiftOracle() {
        val ids = listOf("gpt-5", "gpt-5-mini", "gpt-5.4", "gpt-5.5", "gpt-4.1-2025-04-14", "o3", "o4-mini",
            "gpt-5-pro", "gpt-5-pro-2025-10-06", "gpt-5.2-pro", "gpt-5.4-pro", "gpt-5.5-pro",
            "o1-pro", "o3-pro", "gpt-5-codex", "o3-deep-research", "gpt-realtime",
            "gpt-4o-audio-preview", "gpt-image-1", "gpt-4o-transcribe", "gpt-4o-mini-tts", "other-model")
        // Verbatim second stdout line from the compiled Swift oracle (2026-10-23).
        val expected = "gpt-5,gpt-5-mini,gpt-5.4,gpt-5.5,gpt-4.1-2025-04-14,o3,o4-mini"
        assertEquals(expected, ids.filter(OpenAiChatContract::isModelCandidate).joinToString(","))
    }

    @Test fun normalStreamCompletesAndSupportsRefusals() {
        val state = OpenAiChatContract.StreamState()
        assertEquals("I cannot answer that question.", state.consume("""{"choices":[{"delta":{"refusal":"I cannot answer that question."},"finish_reason":"stop"}]}"""))
        state.finish()
        assertTrue(state.receivedPayload)
    }

    @Test fun partialStreamWithoutTerminalEventIsNotSuccessful() {
        val state = OpenAiChatContract.StreamState()
        assertEquals("Partial", state.consume("""{"choices":[{"delta":{"content":"Partial"}}]}"""))
        val error = assertThrows(Exception::class.java) { state.finish() }
        assertTrue(error.message!!.contains("before completing"))
        assertEquals("Partial", state.text)
    }

    @Test fun emptyAndReasoningOnlyStreamsAreErrors() {
        val empty = OpenAiChatContract.StreamState()
        empty.consume("[DONE]")
        assertThrows(Exception::class.java) { empty.finish() }
        val limited = OpenAiChatContract.StreamState()
        limited.consume("""{"choices":[{"delta":{},"finish_reason":"length"}]}""")
        val error = assertThrows(Exception::class.java) { limited.finish() }
        assertTrue(error.message!!.contains("before returning an answer"))
    }

    @Test fun truncationStatePreservesTextForTheExistingNotice() {
        val state = OpenAiChatContract.StreamState()
        state.consume("""{"choices":[{"delta":{"content":"Partial"},"finish_reason":"length"}]}""")
        state.finish()
        assertEquals("Partial", state.text)
        assertEquals("length", state.finishReason)
    }

    @Test fun providerErrorAndFilterCannotDisappearIntoBlankSuccess() {
        val state = OpenAiChatContract.StreamState()
        val error = assertThrows(Exception::class.java) {
            state.consume("""{"error":{"message":"Insufficient balance"}}""")
        }
        assertTrue(error.message!!.contains("Insufficient balance"))
        val filtered = OpenAiChatContract.StreamState()
        filtered.consume("""{"choices":[{"delta":{"content":"Partial"},"finish_reason":"content_filter"}]}""")
        assertTrue(assertThrows(Exception::class.java) { filtered.finish() }.message!!.contains("filtered"))
    }
}
