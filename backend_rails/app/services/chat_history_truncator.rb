# frozen_string_literal: true

# Drops oldest conversation turns so the LLM payload stays within a safe size.
# Keeps the most recent messages and enforces a rough character budget (proxy for tokens).
class ChatHistoryTruncator
  TRUNCATION_SUFFIX = "\n\n[... message truncated for context limit ...]"

  DEFAULT_MAX_MESSAGES = 48
  DEFAULT_MAX_CONTENT_CHARS = 100_000

  # @param messages [Array<Hash>, nil] each element has :role and :content (String)
  # @return [Array<Hash>] normalized copies, newest-priority, role as String matching DB
  def self.truncate(messages, max_messages: DEFAULT_MAX_MESSAGES, max_content_chars: DEFAULT_MAX_CONTENT_CHARS)
    return [] if messages.blank?

    list = messages.map { |m| normalize(m) }
    list = list.last(max_messages) if list.size > max_messages

    while list.size > 1 && total_content_chars(list) > max_content_chars
      list.shift
    end

    if list.one? && total_content_chars(list) > max_content_chars
      list[0] = truncate_single_message(list.first, max_content_chars)
    end

    strip_leading_assistants(list)
  end

  def self.normalize(msg)
    role = (msg[:role] || msg["role"]).to_s
    content = msg[:content] || msg["content"]
    content = content.is_a?(String) ? content : content.to_s
    { role: role, content: content }
  end

  def self.total_content_chars(list)
    list.sum { |m| m[:content].to_s.length }
  end
  private_class_method :total_content_chars

  def self.truncate_single_message(msg, max_chars)
    body = msg[:content].to_s
    return msg if body.length <= max_chars

    budget = max_chars - TRUNCATION_SUFFIX.length
    budget = [budget, 0].max
    { role: msg[:role], content: body[0, budget].to_s + TRUNCATION_SUFFIX }
  end
  private_class_method :truncate_single_message

  def self.strip_leading_assistants(list)
    while list.first && list.first[:role] == "assistant"
      list.shift
    end
    list
  end
  private_class_method :strip_leading_assistants
end
