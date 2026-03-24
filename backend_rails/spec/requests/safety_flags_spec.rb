# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Safety flags API", type: :request do
  describe "PATCH /api/safety-flags/:id/acknowledge" do
    it "requires authentication" do
      patch "/api/safety-flags/1/acknowledge"

      expect(response).to have_http_status(:unauthorized)
    end

    context "with authenticated therapist" do
      let(:therapist) { create(:therapist) }
      let(:user) { therapist.user }
      let(:headers) { auth_headers_for(user) }
      let(:client) { create(:client, therapist: therapist) }
      let(:session) { create(:session, therapist: therapist, client: client) }
      let(:flag) { create(:safety_flag, session: session, acknowledged: false) }

      it "marks the flag as acknowledged" do
        patch "/api/safety-flags/#{flag.id}/acknowledge", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(flag.reload.acknowledged).to be(true)
        expect(flag.acknowledged_by_id).to eq(user.id)
      end

      it "returns 404 when flag is not on this therapist's caseload" do
        other_therapist = create(:therapist)
        other_client = create(:client, therapist: other_therapist)
        other_session = create(:session, therapist: other_therapist, client: other_client)
        other_flag = create(:safety_flag, session: other_session)

        patch "/api/safety-flags/#{other_flag.id}/acknowledge", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
