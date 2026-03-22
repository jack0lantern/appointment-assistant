class RedactionService
  RedactionMapping = Struct.new(:token, :original, :pii_type, keyword_init: true)
  RedactionResult = Struct.new(:redacted_text, :mappings, keyword_init: true)

  # Pattern definitions — order matters: more specific patterns first.
  SSN_RE = /\b(\d{3}-\d{2}-\d{4})\b|(?<=SSN\s)(\d{9})\b|(?<=ssn\s)(\d{9})\b/
  EMAIL_RE = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/
  DOB_RE = /(?:(?:DOB|dob|date\s+of\s+birth|Date\s+of\s+Birth)\s*:?\s*)(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})/
  POLICY_RE = /(?:(?:policy|member|insurance|group)\s*(?:number|id|#|no\.?)\s*:?\s*)([A-Za-z0-9\-]{6,20})/i
  NAME_RE = /(?:(?:[Pp]atient\s*(?:[Nn]ame)?|[Nn]ame|[Mm]y\s+[Nn]ame\s+[Ii]s|[Cc]lient|[Ii]nsured)\s*:?\s*)([A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)/
  ADDRESS_RE = /\b(\d{1,6}\s+[A-Z][a-zA-Z]*(?:\s+[A-Z][a-zA-Z]*)*\s+(?:Street|St|Avenue|Ave|Boulevard|Blvd|Drive|Dr|Road|Rd|Lane|Ln|Way|Court|Ct|Place|Pl)(?:\s*,\s*[A-Za-z\s]+(?:\s+[A-Z]{2}\s+\d{5})?)?)/i
  PHONE_RE = /\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}/

  # [pattern, pii_type, capture_group (nil = full match)]
  PATTERNS = [
    [SSN_RE, "SSN", nil],
    [EMAIL_RE, "EMAIL", nil],
    [DOB_RE, "DOB", 1],
    [POLICY_RE, "POLICY", 1],
    [NAME_RE, "NAME", 1],
    [ADDRESS_RE, "ADDRESS", nil],
    [PHONE_RE, "PHONE", nil]
  ].freeze

  def initialize
    @original_to_token = {}
    @token_to_original = {}
    @counters = Hash.new(0)
  end

  def redact(text)
    return RedactionResult.new(redacted_text: "", mappings: []) if text.nil? || text.empty?

    mappings = []
    result = text.dup

    PATTERNS.each do |pattern, pii_type, group_idx|
      matches = []
      result.scan(pattern) do
        m = Regexp.last_match
        matches << m
      end

      matches.reverse_each do |m|
        if group_idx
          # Find first non-nil capture group
          original = m[group_idx]
          next if original.nil?
          start_pos = m.begin(group_idx)
          end_pos = m.end(group_idx)
        else
          # SSN has multiple capture groups — find the matched one
          original = m[0]
          start_pos = m.begin(0)
          end_pos = m.end(0)
        end

        token = get_or_create_token(original.strip, pii_type)
        result = result[0...start_pos] + token + result[end_pos..]
        mappings << RedactionMapping.new(
          token: token,
          original: original.strip,
          pii_type: pii_type
        )
      end
    end

    # Deduplicate mappings
    seen = Set.new
    unique_mappings = mappings.select { |m| seen.add?(m.original) }

    RedactionResult.new(redacted_text: result, mappings: unique_mappings)
  end

  def restore(redacted_text)
    result = redacted_text.dup
    @token_to_original.each do |token, original|
      result.gsub!(token, original)
    end
    result
  end

  def filter_fields(data, allowed_fields)
    data.select { |k, _| allowed_fields.include?(k) }
  end

  private

  def get_or_create_token(original, pii_type)
    return @original_to_token[original] if @original_to_token.key?(original)

    @counters[pii_type] += 1
    token = "[#{pii_type}_#{@counters[pii_type]}]"
    @original_to_token[original] = token
    @token_to_original[token] = original
    token
  end
end
