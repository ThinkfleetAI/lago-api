# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CustomerPortal::Subscriptions::Create do
  subject(:result) do
    execute_graphql(
      customer_portal_user: customer,
      query: mutation,
      variables: {input: {planCode: plan_code}}
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:plan) { create(:plan, organization:, code: "aistack-basic") }
  let(:plan_code) { plan.code }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateCustomerPortalSubscriptionInput!) {
        createCustomerPortalSubscription(input: $input) { id externalId plan { code } }
      }
    GQL
  end

  it_behaves_like "requires a customer portal user"

  it "creates a subscription for an available plan" do
    data = result["data"]["createCustomerPortalSubscription"]

    expect(data["plan"]["code"]).to eq("aistack-basic")
    expect(data["externalId"]).to eq("#{customer.external_id}-aistack")
  end

  shared_examples "a rejected plan" do
    it "does not create a subscription" do
      expect { result }.not_to change(Subscription, :count)
      expect_graphql_error(result:, message: "plan_not_found")
    end
  end

  context "when the plan is not self-serve" do
    let(:plan) { create(:plan, organization:, code: "aistack-enterprise", self_serve: false) }

    it_behaves_like "a rejected plan"
  end

  context "when the plan is hidden in the portal" do
    before { create(:item_metadata, organization:, owner: plan, value: {"hidden_in_portal" => "true"}) }

    it_behaves_like "a rejected plan"
  end

  context "when the plan is restricted to products the customer does not have" do
    before { create(:item_metadata, organization:, owner: plan, value: {"visible_to_products" => "memory"}) }

    it_behaves_like "a rejected plan"
  end

  context "when the plan belongs to another organization" do
    let(:plan) { create(:plan, code: "aistack-basic") }

    it_behaves_like "a rejected plan"
  end
end
