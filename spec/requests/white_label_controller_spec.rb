# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhiteLabelController, type: :request do
  let(:agreement) { create(:white_label_agreement) }
  let(:token) { agreement.signing_url.split("/white-label/").last }
  let(:accept_params) { {accept: "1", signer_name: "Jane", signer_title: "CEO", signer_email: "jane@example.com"} }

  describe "GET /white-label/:token" do
    it "renders the gate for a pending agreement" do
      get "/white-label/#{token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("I accept the agreement")
    end
  end

  describe "POST /white-label/:token/accept" do
    it "records the acceptance and continues to payment" do
      post "/white-label/#{token}/accept", params: accept_params

      expect(response).to have_http_status(:found)
      expect(agreement.reload.status).to eq("accepted")
    end

    context "when the signing link is reused after acceptance" do
      before { post "/white-label/#{token}/accept", params: accept_params }

      it "rejects GET requests" do
        get "/white-label/#{token}"

        expect(response).to have_http_status(:not_found)
      end

      it "rejects POST requests" do
        post "/white-label/#{token}/accept", params: accept_params

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when visiting the post-acceptance link and no checkout can be created" do
      before { post "/white-label/#{token}/accept", params: accept_params }

      it "does not redirect to the customer portal" do
        allow(CustomerPortal::GenerateUrlService).to receive(:call).and_call_original
        resume_token = agreement.reload.payment_resume_url.split("/white-label/").last

        get "/white-label/#{resume_token}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("has been signed")
        expect(CustomerPortal::GenerateUrlService).not_to have_received(:call)
      end
    end
  end
end
