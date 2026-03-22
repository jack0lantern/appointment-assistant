class OcrService
  ExtractedField = Struct.new(:field_name, :value, :confidence, keyword_init: true)

  attr_reader :redactor

  NAME_RE = /(?:patient\s*name|name)\s*:\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)/i
  DOB_RE = /(?:DOB|date\s+of\s+birth)\s*:\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i
  POLICY_RE = /(?:policy|member|insurance|group)\s*(?:number|id|#|no\.?)?\s*:\s*([A-Za-z0-9\-]{6,20})/i

  def initialize(redactor: nil)
    @redactor = redactor || RedactionService.new
  end

  def extract_text(_file_data, _filename)
    # Stub — returns demo text. Swap for real OCR backend in production.
    "Patient Name: Demo Patient\nDOB: 01/01/1990\nPolicy Number: DEMO-123456\n" \
    "Group: GRP-001\nInsurance: Demo Health Plan"
  end

  def extract_fields(raw_text)
    fields = []

    if (match = NAME_RE.match(raw_text))
      fields << ExtractedField.new(field_name: "name", value: match[1], confidence: 0.9)
    end

    if (match = DOB_RE.match(raw_text))
      fields << ExtractedField.new(field_name: "date_of_birth", value: match[1], confidence: 0.9)
    end

    if (match = POLICY_RE.match(raw_text))
      fields << ExtractedField.new(field_name: "policy_number", value: match[1], confidence: 0.85)
    end

    fields
  end

  def redact_for_llm(raw_text)
    @redactor.redact(raw_text).redacted_text
  end

  def process_document(file_data, filename, document_type)
    raw_text = extract_text(file_data, filename)
    fields = extract_fields(raw_text)
    redacted_preview = redact_for_llm(raw_text)

    {
      raw_text: raw_text,
      redacted_preview: redacted_preview,
      fields: fields,
      document_type: document_type
    }
  end
end
