# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::WhiteLabelController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:agreement) { create(:white_label_agreement, customer:, organization:) }

  describe "GET /api/v1/white_label/agreements" do
    subject { get_with_token(organization, "/api/v1/white_label/agreements") }

    before { agreement }

    it_behaves_like "requires API permission", "white_label", "read"

    it "lists agreements" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:white_label_agreements].map { |a| a[:lago_id] }).to eq([agreement.id])
    end
  end

  describe "POST /api/v1/white_label/agreements/:id/reset" do
    subject { post_with_token(organization, "/api/v1/white_label/agreements/#{agreement.id}/reset") }

    it_behaves_like "requires API permission", "white_label", "write"
  end

  describe "POST /api/v1/white_label/provision" do
    subject { post_with_token(organization, "/api/v1/white_label/provision", {external_id: "ext", plan_code: "missing"}) }

    it_behaves_like "requires API permission", "white_label", "write"
  end
end
