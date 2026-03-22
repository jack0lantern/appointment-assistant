# frozen_string_literal: true

module Api
  class AgentController < ApplicationController
    include Authenticatable

    # POST /api/agent/chat
    def chat
      message = params[:message]

      if message.blank?
        render json: { error: "Message is required" }, status: :unprocessable_entity
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
