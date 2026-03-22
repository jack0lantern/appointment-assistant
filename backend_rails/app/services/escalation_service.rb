# frozen_string_literal: true

# Handles human escalation for conversations that exceed safety thresholds.
# Stub implementation: logs events and pauses conversations; future versions
# will send webhooks / alerts to staff.
class EscalationService
  MEDIUM_RISK_THRESHOLD = 3

  # Escalate a conversation immediately (e.g. crisis detection).
  #
  # @param conversation [Conversation]
  # @param reason [String] why the escalation occurred
  # @param risk_level [String] the risk level that triggered escalation
  # @return [Hash] { escalated: true, conversation_id: <uuid> }
  def self.escalate(conversation:, reason:, risk_level:)
    conversation.update!(status: "paused")

    Rails.logger.info(
      "[EscalationService] Escalation triggered — " \
      "conversation_id=#{conversation.uuid} reason=#{reason} risk_level=#{risk_level}"
    )

    alert_staff(conversation_id: conversation.uuid, reason: reason)

    { escalated: true, conversation_id: conversation.uuid }
  end

  # Check whether accumulated medium-risk turns warrant auto-escalation.
  #
  # @param conversation [Conversation]
  # @return [Boolean] true if escalation was triggered
  def self.check_accumulated_risk(conversation:)
    progress = conversation.onboarding

    if progress.medium_risk_count >= MEDIUM_RISK_THRESHOLD
      escalate(
        conversation: conversation,
        reason: "accumulated_medium_risk",
        risk_level: "medium"
      )
      true
    else
      false
    end
  end

  # Stub: will be replaced with a real webhook/notification in the future.
  #
  # @param conversation_id [String]
  # @param reason [String]
  def self.alert_staff(conversation_id:, reason:)
    Rails.logger.info(
      "[EscalationService] STUB alert_staff — " \
      "conversation_id=#{conversation_id} reason=#{reason}"
    )
    # No-op: future webhook integration point
  end
end
