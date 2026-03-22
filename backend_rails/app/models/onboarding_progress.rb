# frozen_string_literal: true

# Value object backed by the onboarding_progress JSONB column on Conversation.
# Tracks where a user is in the onboarding funnel.
class OnboardingProgress
  MAX_UPLOADED_DOCUMENTS = 10

  ATTRIBUTES = %i[
    is_new_user
    has_completed_intake
    assigned_therapist_id
    selected_therapist_id
    risk_level
    docs_verified
    appointment_id
    medium_risk_count
    uploaded_documents
  ].freeze

  attr_accessor(*ATTRIBUTES)

  def initialize(attrs = {})
    attrs = (attrs || {}).symbolize_keys
    @is_new_user           = attrs.fetch(:is_new_user, false)
    @has_completed_intake  = attrs.fetch(:has_completed_intake, false)
    @assigned_therapist_id = attrs[:assigned_therapist_id]
    @selected_therapist_id = attrs[:selected_therapist_id]
    @risk_level            = attrs[:risk_level]
    @docs_verified         = attrs.fetch(:docs_verified, false)
    @appointment_id        = attrs[:appointment_id]
    @medium_risk_count     = attrs.fetch(:medium_risk_count, 0)
    raw_docs               = attrs[:uploaded_documents]
    @uploaded_documents    = normalize_uploaded_documents(raw_docs)
  end

  def to_h
    {
      is_new_user: is_new_user,
      has_completed_intake: has_completed_intake,
      assigned_therapist_id: assigned_therapist_id,
      selected_therapist_id: selected_therapist_id,
      risk_level: risk_level,
      docs_verified: docs_verified,
      appointment_id: appointment_id,
      medium_risk_count: medium_risk_count,
      uploaded_documents: uploaded_documents
    }
  end

  def add_uploaded_document(document_ref:, redacted_preview:, status: "verified")
    entry = { document_ref: document_ref, redacted_preview: redacted_preview, status: status }
    @uploaded_documents = ([entry] + @uploaded_documents).first(MAX_UPLOADED_DOCUMENTS)
  end

  def find_document(document_ref)
    ref_str = document_ref.to_s
    doc = uploaded_documents.find { |d| (d[:document_ref] || d["document_ref"])&.to_s == ref_str }
    return nil unless doc

    {
      document_ref: (doc[:document_ref] || doc["document_ref"])&.to_s,
      redacted_preview: (doc[:redacted_preview] || doc["redacted_preview"])&.to_s,
      status: (doc[:status] || doc["status"])&.to_s || "verified"
    }
  end

  private

  def normalize_uploaded_documents(raw)
    return [] if raw.blank?

    Array(raw).filter_map do |d|
      h = d.is_a?(Hash) ? d : {}
      ref = (h[:document_ref] || h["document_ref"])&.to_s
      next if ref.blank?

      {
        document_ref: ref,
        redacted_preview: (h[:redacted_preview] || h["redacted_preview"])&.to_s,
        status: (h[:status] || h["status"])&.to_s.presence || "verified"
      }
    end
  end

  def self.from_hash(hash)
    new(hash)
  end

  def ==(other)
    other.is_a?(OnboardingProgress) && to_h == other.to_h
  end
end
