package com.noop.ai

import org.json.JSONObject

/** Chat Completions wire policy; mirrors Swift OpenAIChatTransport without model-name guesses. */
internal object OpenAiChatContract {
    const val OUTPUT_TOKEN_LIMIT = 4096

    /** Catalog-only exclusion of known specialized/Responses-only models; never changes selection.
     * Source: https://developers.openai.com/api/docs/models (verified 2026-10-23). */
    fun isModelCandidate(id: String): Boolean {
        if (!id.startsWith("gpt-") && !Regex("^o[0-9]+(?:-|$)").containsMatchIn(id)) return false
        val specialized = listOf("audio", "realtime", "transcribe", "tts", "image", "embedding", "deep-research", "codex")
        if (specialized.any { id.contains("-$it") }) return false
        val responsesOnly = listOf("gpt-5-pro", "gpt-5.2-pro", "gpt-5.4-pro", "gpt-5.5-pro", "o1-pro", "o3-pro")
        return responsesOnly.none { id == it || id.startsWith("$it-") }
    }

    fun parameters(body: JSONObject, modern: Boolean): JSONObject = body.apply {
        put(if (modern) "max_completion_tokens" else "max_tokens", OUTPUT_TOKEN_LIMIT)
        if (!modern) put("temperature", 0.6)
    }

    fun shouldRetryModernParams(status: Int, detail: String): Boolean {
        if (status != 400) return false
        val lower = detail.lowercase()
        val legacyParameter = lower.contains("max_tokens") || lower.contains("temperature")
        val rejection = listOf("unsupported", "not supported", "not support", "unknown parameter",
            "unrecognized", "not allowed", "only the default", "use 'max_completion_tokens'",
            "use max_completion_tokens").any { lower.contains(it) }
        return legacyParameter && rejection
    }

    fun validateReply(content: String, finishReason: String?, fallbackMessage: String) {
        if (finishReason == "content_filter") {
            throw Exception("The provider filtered this reply. Rephrase your question and try again.")
        }
        if (content.isBlank()) {
            if (finishReason == "length") {
                throw Exception("The model reached its response limit before returning an answer. " +
                    "Ask a shorter question or select another model.")
            }
            throw Exception(fallbackMessage)
        }
    }

    class StreamState {
        var receivedPayload = false
            private set
        var text = ""
            private set
        var finishReason: String? = null
            private set
        private var completed = false

        fun consume(payload: String): String? {
            receivedPayload = true
            if (payload.trim() == "[DONE]") { completed = true; return null }
            val json = JSONObject(payload)
            if (json.has("error")) throw Exception(AiCoach.emptyReplyMessage(payload))
            val choice = json.optJSONArray("choices")?.optJSONObject(0) ?: return null
            choice.optString("finish_reason").takeUnless { it.isNullOrEmpty() || it == "null" }?.let {
                finishReason = it.lowercase()
                completed = true
            }
            val delta = choice.optJSONObject("delta") ?: return null
            val piece = when {
                delta.opt("content") is String -> delta.getString("content")
                delta.opt("refusal") is String -> delta.getString("refusal")
                else -> null
            }
            if (piece != null) text += piece
            return piece
        }

        fun finish() {
            validateReply(text, finishReason, AiCoach.emptyReplyMessage("{}"))
            if (!completed) throw Exception("The provider closed the stream before completing its reply")
        }
    }
}
