# frozen_string_literal: true

module Api
  class OnboardController < ApplicationController
    include Authenticatable

    # GET /api/onboard/:slug
    def show
      therapist = Therapist.find_by(slug: params[:slug])

      if therapist.nil?
        render json: { error: "Therapist not found" }, status: :not_found
        return
      end

      conversation = find_or_create_onboarding_conversation(therapist)

      render json: {
        conversation_id: conversation.uuid,
        therapist_name: therapist.user.name,
        context_type: "onboarding",
        welcome_message: "Welcome! You've been connected with #{therapist.user.name}. " \
                         "Let's get you set up for your first appointment."
      }
    end

    private

    def find_or_create_onboarding_conversation(therapist)
      # Find existing active onboarding conversation for this user
      existing = current_user.conversations.find_by(
        context_type: "onboarding",
        status: "active"
      )

      return existing if existing

      # Create a new onboarding conversation
      current_user.conversations.create!(
        context_type: "onboarding",
        status: "active",
        title: "Onboarding with #{therapist.user.name}",
        onboarding_progress: { "assigned_therapist_id" => therapist.id }
      )
    end
  end
end
