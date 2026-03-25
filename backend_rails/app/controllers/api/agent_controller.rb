# frozen_string_literal: true

module Api
  class AgentController < ApplicationController
    include Authenticatable

    # Single-turn user text cap (characters). Documented in docs/CHAT_LIMITS.md (keep in sync with
    # frontend/src/lib/chatLimits.ts). DB stores full threads; `ChatHistoryTruncator` limits what is sent to the LLM.
    MAX_CHAT_MESSAGE_CHARS = 16_384

    # POST /api/agent/chat
    def chat
      message = params[:message]

      if message.blank?
        render json: { error: "Message is required" }, status: :unprocessable_entity
        return
      end

      if message.to_s.length > MAX_CHAT_MESSAGE_CHARS
        render json: {
          error: "Your message is too long (maximum #{MAX_CHAT_MESSAGE_CHARS} characters). " \
            "Shorten it or start a new chat."
        }, status: :unprocessable_entity
        return
      end

      unless ENV["ANTHROPIC_API_KEY"].present?
        render json: { error: "AI service is not configured. Set ANTHROPIC_API_KEY in .env" },
          status: :service_unavailable
        return
      end

      service = AgentService.new
      response = service.process_message(
        message: message,
        user: current_user,
        conversation_id: params[:conversation_id],
        context_type: params[:context_type] || "general",
        page_context: params[:page_context]
      )

      render json: response
    end
  end
end
