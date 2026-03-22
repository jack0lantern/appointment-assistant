# frozen_string_literal: true

class TherapistSearchService
  TherapistSearchResult = Struct.new(
    :display_label, :name, :license_type, :specialties, :bio,
    keyword_init: true
  )

  def initialize
    @label_map = {} # display_label => therapist_id
  end

  # Search therapists by name, specialty, gender, or insurance.
  # Returns an array of TherapistSearchResult structs with display labels (no raw IDs).
  def search(query: nil, specialty: nil, gender: nil, insurance: nil)
    scope = Therapist.joins(:user)

    if query.present?
      scope = scope.where("users.name ILIKE ?", "%#{sanitize_like(query)}%")
    end

    results = scope.includes(:user).to_a

    # Filter by specialty in Ruby (JSONB array)
    if specialty.present?
      downcased = specialty.downcase
      results = results.select do |t|
        Array(t.specialties).any? { |s| s.to_s.downcase.include?(downcased) }
      end
    end

    @label_map = {}
    results.each_with_index.map do |therapist, index|
      label = generate_label(therapist, index)
      @label_map[label] = therapist.id

      TherapistSearchResult.new(
        display_label: label,
        name: therapist.user.name,
        license_type: therapist.license_type,
        specialties: Array(therapist.specialties),
        bio: therapist.preferences&.dig("bio") || ""
      )
    end
  end

  # Resolve a display label back to a real therapist ID.
  def resolve_label(display_label)
    @label_map[display_label]
  end

  # Confirm therapist selection: saves the selected_therapist_id into the
  # conversation's onboarding_progress.
  def confirm_selection(conversation:, display_label:)
    therapist_id = resolve_label(display_label)
    return nil unless therapist_id

    progress = conversation.onboarding_progress || {}
    progress["selected_therapist_id"] = therapist_id
    conversation.update!(onboarding_progress: progress)
    therapist_id
  end

  private

  def generate_label(therapist, index)
    letter = ("A".."Z").to_a[index % 26]
    "Dr. #{letter}"
  end

  def sanitize_like(str)
    str.gsub(/[%_\\]/) { |m| "\\#{m}" }
  end
end
