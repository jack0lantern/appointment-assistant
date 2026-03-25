# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent Chat", type: :request do
  describe "POST /api/agent/chat" do
    it "requires authentication" do
      post "/api/agent/chat", params: { message: "Hello" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated user" do
      let(:user) { create(:user, :client) }
      let(:headers) { auth_headers_for(user) }

      it "rejects empty message" do
        post "/api/agent/chat", params: { message: "" }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects missing message" do
        post "/api/agent/chat", params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects message over max length and instructs starting a new chat" do
        max = Api::AgentController::MAX_CHAT_MESSAGE_CHARS
        body = "a" * (max + 1)

        post "/api/agent/chat", params: { message: body }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
        expect(json["error"].downcase).to include("new chat")
      end

      it "accepts message at exactly max length" do
        mock_llm = instance_double(LlmService)
        allow(LlmService).to receive(:new).and_return(mock_llm)
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "OK" }]
        )

        max = Api::AgentController::MAX_CHAT_MESSAGE_CHARS
        body = "a" * max

        post "/api/agent/chat", params: { message: body }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
      end

      it "returns expected response shape" do
        mock_llm = instance_double(LlmService)
        allow(LlmService).to receive(:new).and_return(mock_llm)
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "Hello! How can I help you today?" }]
        )

        post "/api/agent/chat", params: { message: "Hello" }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to have_key("message")
        expect(json).to have_key("conversation_id")
        expect(json).to have_key("suggested_actions")
        expect(json).to have_key("safety")
        expect(json).to have_key("context_type")
        expect(json).to have_key("follow_up_questions")
      end

      it "passes context_type through" do
        mock_llm = instance_double(LlmService)
        allow(LlmService).to receive(:new).and_return(mock_llm)
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "Let me help you get started." }]
        )

        post "/api/agent/chat",
             params: { message: "I'm new here", context_type: "onboarding" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["context_type"]).to eq("onboarding")
      end

      it "creates a conversation" do
        mock_llm = instance_double(LlmService)
        allow(LlmService).to receive(:new).and_return(mock_llm)
        allow(mock_llm).to receive(:call).and_return(
          "content" => [{ "type" => "text", "text" => "Hello!" }]
        )

        expect {
          post "/api/agent/chat", params: { message: "Hello" }, headers: headers, as: :json
        }.to change(Conversation, :count).by(1)
      end

      it "handles crisis messages with safety flag" do
        mock_llm = instance_double(LlmService)
        allow(LlmService).to receive(:new).and_return(mock_llm)

        post "/api/agent/chat",
             params: { message: "I want to kill myself" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["safety"]["flagged"]).to be true
        expect(json["safety"]["escalated"]).to be true
        expect(json["message"]).to include("988")
      end
    end
  end
end
