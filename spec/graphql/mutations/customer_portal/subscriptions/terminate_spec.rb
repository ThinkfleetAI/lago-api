# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CustomerPortal::Subscriptions::Terminate do
  subject(:result) do
    execute_graphql(
      customer_portal_user: customer,
      query: mutation,
      variables: {input: {productKey: product_key}}
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, code: "aistack-basic") }
  let!(:subscription) do
    create(:subscription, customer:, organization:, plan:, external_id: "#{customer.external_id}-aistack")
  end

  let(:mutation) do
    <<~GQL
      mutation($input: TerminateCustomerPortalSubscriptionInput!) {
        terminateCustomerPortalSubscription(input: $input) { id status }
      }
    GQL
  end

  it_behaves_like "requires a customer portal user"

  context "with the product key of an active subscription" do
    let(:product_key) { "aistack" }

    it "terminates the subscription" do
      expect(result["data"]["terminateCustomerPortalSubscription"]["status"]).to eq("terminated")
      expect(subscription.reload).to be_terminated
    end
  end

  %w[% _ aistac_ %stack].each do |key|
    context "with the wildcard product key #{key.inspect}" do
      let(:product_key) { key }

      it "does not terminate anything" do
        expect_graphql_error(result:, message: "no_active_subscription_for_product")
        expect(subscription.reload).to be_active
      end
    end
  end
end
