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

    get "therapist/appointments" => "therapist_appointments#index"
    get "my/appointments" => "client_appointments#index"

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
