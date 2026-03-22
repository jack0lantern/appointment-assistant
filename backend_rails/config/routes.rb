Rails.application.routes.draw do
  get "health" => "health#show"
  get "up" => "rails/health#show", as: :rails_health_check

  post "api/auth/login" => "auth#login"

  namespace :api do
    post "agent/chat" => "agent#chat"
    get "agent/scheduling/availability" => "agent_scheduling#availability"
    post "agent/scheduling/book" => "agent_scheduling#book"
    post "agent/scheduling/cancel" => "agent_scheduling#cancel"

    post "agent/documents/upload" => "documents#upload"

    get "onboard/:slug" => "onboard#show"
  end
end
