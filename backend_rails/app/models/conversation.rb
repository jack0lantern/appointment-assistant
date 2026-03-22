class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, class_name: "ConversationMessage", dependent: :destroy

  validates :uuid, presence: true, uniqueness: true
  validates :context_type, presence: true, inclusion: {
    in: %w[general onboarding scheduling emotional_support document_upload]
  }
  validates :status, presence: true, inclusion: { in: %w[active paused] }

  before_validation :set_uuid, on: :create

  def paused?
    status == "paused"
  end

  # Deserialize onboarding_progress JSONB into an OnboardingProgress value object.
  def onboarding
    OnboardingProgress.from_hash(onboarding_progress || {})
  end

  # Serialize an OnboardingProgress value object back to JSONB.
  def onboarding=(progress)
    self.onboarding_progress = progress.is_a?(OnboardingProgress) ? progress.to_h : progress
  end

  # Convenience: update onboarding progress and persist in one call.
  def save_onboarding!(progress)
    self.onboarding = progress
    save!
  end

  private

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
