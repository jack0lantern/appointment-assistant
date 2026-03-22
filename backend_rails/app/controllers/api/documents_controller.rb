# frozen_string_literal: true

module Api
  class DocumentsController < ApplicationController
    include Authenticatable

    # POST /api/agent/documents/upload
    def upload
      file = params[:file]

      if file.blank?
        render json: { error: "File is required" }, status: :unprocessable_entity
        return
      end

      conversation = find_conversation
      document_type = params[:document_type] || "unknown"

      service = DocumentProcessorService.new
      result = service.process(
        file_data: file.respond_to?(:read) ? file.read : file,
        filename: file.respond_to?(:original_filename) ? file.original_filename : file.to_s,
        document_type: document_type,
        conversation: conversation
      )

      render json: {
        document_ref: result[:document_ref],
        fields: result[:fields],
        redacted_preview: result[:redacted_preview],
        status: result[:status]
      }
    rescue DocumentProcessorService::InvalidFileTypeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue DocumentProcessorService::FileTooLargeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def find_conversation
      return nil unless params[:conversation_id].present?

      current_user.conversations.find_by(id: params[:conversation_id])
    end
  end
end
