Rails.application.routes.draw do
  get "health" => "health#show"
  get "up" => "rails/health#show", as: :rails_health_check

  post "api/auth/login" => "auth#login"
  post "api/auth/client/login" => "auth#client_login"
  post "api/auth/therapist/login" => "auth#therapist_login"

  namespace :api do
    get "clients" => "clients#index"
    post "clients" => "clients#create"
    get "clients/:id" => "clients#show"
    post "clients/:client_id/sessions/live" => "live_sessions#create"
    post "sessions/:session_id/live/token" => "live_sessions#token"
    post "sessions/:session_id/live/end" => "live_sessions#end_session"

    get "therapist/appointments" => "therapist_appointments#index"
    get "my/appointments" => "client_appointments#index"
    get "my/sessions" => "client_sessions#index"
    get "my/treatment-plan" => "my_treatment_plans#show"
    get "my/homework" => "homework#index"
    patch "homework/:id" => "homework#update"

    get "treatment-plans/draft" => "treatment_plans#draft"
    post "treatment-plans/:id/approve" => "treatment_plans#approve"
    post "treatment-plans/:id/edit" => "treatment_plans#edit"
    get "treatment-plans/:id/versions" => "treatment_plans#versions"
    get "treatment-plans/:id/diff" => "treatment_plans#diff"
    patch "safety-flags/:id/acknowledge" => "safety_flags#acknowledge"

    post "agent/chat" => "agent#chat"
    get "agent/scheduling/availability" => "agent_scheduling#availability"
    post "agent/scheduling/book" => "agent_scheduling#book"
    post "agent/scheduling/cancel" => "agent_scheduling#cancel"

    post "agent/documents/upload" => "documents#upload"

    get "onboard/:slug" => "onboard#show"

    # Evaluation (SSE streaming)
    post "evaluation/run" => "evaluations#run"
    post "evaluation/run/structural" => "evaluations#run_structural"
    post "evaluation/run/readability" => "evaluations#run_readability"
    post "evaluation/run/safety" => "evaluations#run_safety"
    post "evaluation/stop" => "evaluations#stop"
    get "evaluation/results" => "evaluations#results"
  end

  # SPA fallback: serve index.html for non-API paths (Docker deployment)
  root to: "static#index"
  get "*path", to: "static#index", constraints: ->(req) {
    !req.path.start_with?("/api") && !req.path.start_with?("/health") && !req.path.start_with?("/up")
  }
end
