class AuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:login, :client_login, :therapist_login], raise: false

  def login
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      token = JwtService.encode({ user_id: user.id, role: user.role })
      render json: {
        token: token,
        user: UserBlueprint.render_as_hash(user)
      }
    else
      render json: { error: "Invalid email or password" }, status: :unauthorized
    end
  end

  def client_login
    role_login("client", "therapist", allow_roles: %w[client])
  end

  def therapist_login
    role_login("therapist", "client", allow_roles: %w[therapist admin])
  end

  private

  def role_login(expected_role, other_role, allow_roles: [expected_role])
    user = User.find_by(email: params[:email])
    return render json: { error: "Invalid email or password" }, status: :unauthorized unless user&.authenticate(params[:password])

    unless allow_roles.include?(user.role)
      render json: { error: "This account is for #{other_role}s. Please use the #{other_role} login." }, status: :forbidden
    else
      token = JwtService.encode({ user_id: user.id, role: user.role })
      response_body = {
        token: token,
        user: UserBlueprint.render_as_hash(user)
      }

      if expected_role == "client"
        onboard_info = client_onboarding_info(user)
        response_body.merge!(onboard_info) if onboard_info
      end

      render json: response_body
    end
  end

  def client_onboarding_info(user)
    demo_new_patient = user.email == OnboardingRouter::DEMO_NEW_PATIENT_EMAIL
    # Demo new-patient user always needs onboarding
    needs = demo_new_patient

    # Users without a client profile need onboarding
    needs ||= user.client_profile.nil?

    return nil unless needs

    client = user.client_profile
    slug = client&.therapist&.slug
    # Referral flow: frontend stores slug in localStorage when user opens /onboard/:slug
    # before login. Do not infer a therapist from seed/demo client rows for the demo patient.
    slug = nil if demo_new_patient

    { needs_onboarding: true, onboard_slug: slug }.compact
  end
end
