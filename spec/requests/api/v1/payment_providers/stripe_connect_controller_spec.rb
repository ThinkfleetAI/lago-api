# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PaymentProviders::StripeConnectController do
  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:platform_provider) { create(:stripe_provider, organization:) }

  describe "POST /api/v1/payment_providers/stripe_connect" do
    subject { post_with_token(organization, "/api/v1/payment_providers/stripe_connect", params) }

    let(:params) do
      {
        payment_provider: {
          code: "stripe_reseller_abc",
          name: "Acme Agency (Stripe)",
          billing_entity_code: billing_entity.code,
          connected_account_id: "acct_123"
        }
      }
    end

    before do
      billing_entity
      platform_provider
    end

    it "creates an entity-scoped connected Stripe provider on the platform key" do
      expect { subject }.to change(PaymentProviders::StripeProvider, :count).by(1)
      expect(response).to be_successful

      provider = PaymentProviders::StripeProvider.find_by(code: "stripe_reseller_abc")
      expect(provider).to be_present
      expect(provider.connected_account_id).to eq("acct_123")
      expect(provider.billing_entity_id).to eq(billing_entity.id)
      # Reuses the org's platform Stripe key (no secret is sent over the wire).
      expect(provider.secret_key).to eq(platform_provider.secret_key)
      expect(json[:payment_provider][:code]).to eq("stripe_reseller_abc")
    end

    it "produces connected request options that carry the Stripe-Account header" do
      subject
      provider = PaymentProviders::StripeProvider.find_by(code: "stripe_reseller_abc")
      expect(provider.stripe_request_options).to eq(
        api_key: platform_provider.secret_key,
        stripe_account: "acct_123"
      )
    end

    context "when the organization has no platform Stripe provider" do
      let(:platform_provider) { nil }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the billing entity code is unknown" do
      let(:params) do
        {
          payment_provider: {
            code: "stripe_reseller_x",
            name: "x",
            billing_entity_code: "does-not-exist",
            connected_account_id: "acct_1"
          }
        }
      end

      it "does not create a provider and fails" do
        expect { subject }.not_to change(PaymentProviders::StripeProvider, :count)
        expect(response).not_to be_successful
      end
    end
  end
end
