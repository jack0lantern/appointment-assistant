# frozen_string_literal: true

module Api
  class EvaluationsController < ApplicationController
    include Authenticatable

    before_action :require_therapist

    # POST /api/evaluation/run (and /run/structural, /run/readability, /run/safety)
    def run
      stream_evaluation(section: nil)
    end

    def run_structural
      stream_evaluation(section: "structural")
    end

    def run_readability
      stream_evaluation(section: "readability")
    end

    def run_safety
      stream_evaluation(section: "safety")
    end

    # POST /api/evaluation/stop
    def stop
      # Cancel flag would be checked by a long-running stream; stub returns OK
      render json: { message: "Evaluation stop requested" }
    end

    # GET /api/evaluation/results
    def results
      runs = EvaluationRun.order(run_at: :desc).limit(10)
      payload = runs.map { |r| r.results }
      render json: payload
    end

    private

    def require_therapist
      return if current_user.therapist_profile.present?

      render json: { error: "Therapist access required" }, status: :forbidden
    end

    def stream_evaluation(section:)
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"
      response.headers["X-Accel-Buffering"] = "no"

      self.response_body = Enumerator.new do |yielder|
        label = section ? "#{section} validation" : "evaluation"
        yielder << sse_event("progress", { message: "Starting #{label}..." })

        # Evaluation pipeline (treatment plan generation + structural/readability/safety checks)
        # is planned for future implementation. Full treatment plan pipeline not yet in Rails.
        # See docs/TEST_PARITY_MATRIX.md and docs/IMPLEMENTATION_PLAN.md.
        yielder << sse_event(
          "error",
          {
            message: "Evaluation is not yet implemented in the Rails backend. " \
                     "The treatment plan pipeline and evaluation logic are planned for future implementation. " \
                     "Run: cd backend && uvicorn app.main:app --port 8001, " \
                     "then set VITE_API_URL=http://localhost:8001 when using the Evaluation page."
          }
        )
      end
    end

    def sse_event(event, data)
      "event: #{event}\ndata: #{data.to_json}\n\n"
    end
  end
end
