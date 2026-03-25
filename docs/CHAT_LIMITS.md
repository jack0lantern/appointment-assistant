# Chat limits

This document is the source of truth for user-visible chat constraints. When you change a number here, update the implementations listed below.

## Single message length

| Limit | Value | Where enforced |
|-------|--------|----------------|
| Maximum characters per user message (one `POST /api/agent/chat` `message`) | **16,384** Unicode characters (`String#length` in Ruby; JavaScript string length) | Rails: `Api::AgentController::MAX_CHAT_MESSAGE_CHARS` — rejects over limit with **422** and `{ "error": "..." }`. React: `frontend/src/lib/chatLimits.ts` → `ChatInput` (`maxLength`) and `useChat` (guard before send). |

**Not the same as the model context window.** On each turn the server loads conversation history, then **`ChatHistoryTruncator`** keeps only the **most recent** messages and enforces a **character budget** on history content before calling the LLM (`AgentService` → `ContextBuilder`). Older turns are dropped from the model context only; stored messages in the database are unchanged.

| Limit | Value | Where |
|-------|--------|-------|
| Maximum history **messages** sent to the LLM (not counting the current user turn added by `ContextBuilder`) | **48** | `ChatHistoryTruncator::DEFAULT_MAX_MESSAGES` |
| Maximum **total characters** of history content (all kept history messages’ `content` combined) | **100,000** | `ChatHistoryTruncator::DEFAULT_MAX_CONTENT_CHARS` |

If a single stored message exceeds the character budget alone, its text is truncated with a suffix (`ChatHistoryTruncator::TRUNCATION_SUFFIX`). Leading `assistant` messages are removed after trimming so the history slice starts with a `user` message when possible.

**Over-limit behavior:** The server returns an error asking the user to shorten the message or **start a new chat** (new conversation) so the thread does not keep growing.

## LLM reply length (backend)

| Limit | Value | Where |
|-------|--------|--------|
| Maximum tokens in the assistant’s **generated** reply (one API call) | **1,024** | `LlmService::DEFAULT_MAX_TOKENS` |

This caps how long a single model response can be, not how much prior chat you send in.

## Related

- Crisis and safety flows may short-circuit before the LLM; they are unrelated to these numeric caps.
