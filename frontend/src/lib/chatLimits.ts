/**
 * Chat input limits — keep in sync with `docs/CHAT_LIMITS.md` and
 * `Api::AgentController::MAX_CHAT_MESSAGE_CHARS` in the Rails app.
 */
export const MAX_CHAT_MESSAGE_CHARS = 16_384

export function chatMessageLengthExceededError(): string {
  return `Your message is too long (maximum ${MAX_CHAT_MESSAGE_CHARS} characters). Shorten it or start a new chat.`
}
