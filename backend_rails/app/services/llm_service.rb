# frozen_string_literal: true

# Claude API integration service.
# Wraps the Anthropic SDK to send messages with tool definitions.
class LlmService
  MODEL = "claude-haiku-4-5-20251001"
  DEFAULT_MAX_TOKENS = 1024

  # Allow injecting a client for testing.
  attr_reader :client

  def initialize(client: nil)
    @client = client || build_default_client
  end

  # Send a message to Claude and return the raw API response.
  #
  # @param system_prompt [String]
  # @param messages [Array<Hash>] conversation messages
  # @param tools [Array<Hash>] tool definitions
  # @param max_tokens [Integer]
  # @return [Hash] raw API response body
  def call(system_prompt:, messages:, tools:, max_tokens: DEFAULT_MAX_TOKENS)
    @client.messages(
      parameters: {
        model: MODEL,
        max_tokens: max_tokens,
        system: system_prompt,
        messages: messages,
        tools: tools
      }
    )
  end

  private

  def build_default_client
    api_key = ENV.fetch("ANTHROPIC_API_KEY") { raise "ANTHROPIC_API_KEY is not set" }
    Anthropic::Client.new(access_token: api_key)
  end
end
