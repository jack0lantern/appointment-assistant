# frozen_string_literal: true

# Determines onboarding state for a user and updates the conversation's
# OnboardingProgress accordingly.
#
# Returns { context_type:, onboarding_progress: }
class OnboardingRouter
  # Demo user always routed as new patient for showcasing intake flow
  DEMO_NEW_PATIENT_EMAIL = "jordan.kim@demo.health"

  # Route a user through the onboarding funnel.
  #
  # @param user [User] the authenticated user
  # @param conversation [Conversation] current conversation
  # @return [Hash] { context_type: String, onboarding_progress: OnboardingProgress }
  def self.route(user:, conversation:)
    progress = conversation.onboarding
    client = user.client_profile

    if user.email == DEMO_NEW_PATIENT_EMAIL
      # Hardcoded: Jordan always treated as new patient for demo
      progress.is_new_user = true
      # Don't reset has_completed_intake if already marked true by complete_intake tool
      progress.has_completed_intake = false unless progress.has_completed_intake
      context_type = "onboarding"
    elsif client.nil?
      # Brand-new user with no Client record
      progress.is_new_user = true
      # Don't reset has_completed_intake if already marked true by complete_intake tool
      progress.has_completed_intake = false unless progress.has_completed_intake
      context_type = "onboarding"
    elsif needs_therapist_selection?(client, progress)
      # Returning user but needs to select a therapist
      progress.is_new_user = false
      progress.has_completed_intake = true
      context_type = "onboarding"
    else
      # Returning user with therapist — ready to schedule
      progress.is_new_user = false
      progress.has_completed_intake = true
      progress.assigned_therapist_id ||= client.therapist_id
      context_type = "scheduling"
    end

    conversation.save_onboarding!(progress)

    { context_type: context_type, onboarding_progress: progress }
  end

  # A user needs therapist selection when:
  # - Their onboarding progress explicitly flags needing search
  #   (selected_therapist_id and assigned_therapist_id are both nil on progress,
  #    AND the client record lacks a therapist)
  # In practice with the current schema (therapist_id NOT NULL on clients),
  # this path is triggered by explicit progress state indicating search needed.
  def self.needs_therapist_selection?(client, progress)
    return false if progress.assigned_therapist_id.present?
    return false if progress.selected_therapist_id.present?
    return false if client.therapist_id.present?

    true
  end

  private_class_method :needs_therapist_selection?
end
