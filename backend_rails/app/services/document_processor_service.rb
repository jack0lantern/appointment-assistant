# frozen_string_literal: true

class DocumentProcessorService
  class InvalidFileTypeError < StandardError; end
  class FileTooLargeError < StandardError; end

  ALLOWED_EXTENSIONS = %w[jpg jpeg png pdf gif].freeze
  MAX_FILE_SIZE = 10.megabytes

  def initialize(ocr_service: nil)
    @ocr_service = ocr_service || OcrService.new
  end

  # Process an uploaded document: validate, OCR, extract fields, redact, update onboarding.
  #
  # @param file_data [String] raw file content (or an UploadedFile)
  # @param filename [String] original filename
  # @param document_type [String] e.g. "insurance_card", "id"
  # @param conversation [Conversation, nil] conversation to update onboarding progress on
  # @return [Hash] { document_ref:, fields:, redacted_preview:, raw_text:, status: }
  def process(file_data:, filename:, document_type:, conversation: nil)
    validate_file_type!(filename)
    validate_file_size!(file_data)

    result = @ocr_service.process_document(file_data, filename, document_type)
    document_ref = SecureRandom.uuid

    if conversation
      update_onboarding!(
        conversation,
        document_ref: document_ref,
        redacted_preview: result[:redacted_preview],
        status: "verified"
      )
    end

    {
      document_ref: document_ref,
      fields: serialize_fields(result[:fields]),
      redacted_preview: result[:redacted_preview],
      raw_text: result[:raw_text],
      status: "verified"
    }
  end

  private

  def validate_file_type!(filename)
    ext = File.extname(filename.to_s).delete(".").downcase
    return if ALLOWED_EXTENSIONS.include?(ext)

    raise InvalidFileTypeError, "File type '.#{ext}' is not allowed. Accepted types: #{ALLOWED_EXTENSIONS.join(', ')}"
  end

  def validate_file_size!(file_data)
    size = file_data.respond_to?(:size) ? file_data.size : file_data.to_s.bytesize
    return if size <= MAX_FILE_SIZE

    raise FileTooLargeError, "File exceeds maximum size of 10 MB"
  end

  def update_onboarding!(conversation, document_ref:, redacted_preview:, status:)
    progress = conversation.onboarding
    progress.docs_verified = true
    progress.add_uploaded_document(
      document_ref: document_ref,
      redacted_preview: redacted_preview,
      status: status
    )
    conversation.save_onboarding!(progress)
  end

  def serialize_fields(fields)
    fields.map do |f|
      { field_name: f.field_name, value: f.value, confidence: f.confidence }
    end
  end
end
