class AuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:login], raise: false

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
end
