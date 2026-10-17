# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CustomerPortal::Subscriptions::ChangePlan do
  subject(:result) do
    execute_graphql(
      customer_portal_user: customer,
      query: mutation,
      variables: {input: {planCode: plan_code}}
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:current_plan) { create(:plan, organization:, code: "aistack-basic", amount_cents: 100) }
  let(:target_plan) { create(:plan, organization:, code: "aistack-pro", amount_cents: 200) }
  let(:plan_code) { target_plan.code }
  let!(:subscription) do
    create(:subscription, customer:, organization:, plan: current_plan, external_id: "#{customer.external_id}-aistack")
  end

  let(:mutation) do
    <<~GQL
      mutation($input: ChangeCustomerPortalSubscriptionPlanInput!) {
        changeCustomerPortalSubscriptionPlan(input: $input) { id plan { code } }
      }
    GQL
  end

  it_behaves_like "requires a customer portal user"

  it "switches to an available plan" do
    data = result["data"]["changeCustomerPortalSubscriptionPlan"]

    expect(data["plan"]["code"]).to eq("aistack-pro")
  end

  shared_examples "a rejected plan" do
    it "does not change the subscription" do
      expect_graphql_error(result:, message: "plan_not_found")
      expect(subscription.reload.plan).to eq(current_plan)
      expect(customer.subscriptions.count).to eq(1)
    end
  end

  context "when the target plan is not self-serve" do
    let(:target_plan) { create(:plan, organization:, code: "aistack-enterprise", self_serve: false) }

    it_behaves_like "a rejected plan"
  end

  context "when the target plan is hidden in the portal" do
    before { create(:item_metadata, organization:, owner: target_plan, value: {"hidden_in_portal" => "true"}) }

    it_behaves_like "a rejected plan"
  end

  context "when the target plan is restricted to other products" do
    before { create(:item_metadata, organization:, owner: target_plan, value: {"visible_to_products" => "memory"}) }

    it_behaves_like "a rejected plan"
  end

  context "when the product key contains LIKE wildcards" do
    let(:plan_code) { "%-pro" }

    it "does not match unrelated subscriptions" do
      expect_graphql_error(result:, message: "no_active_subscription_for_product")
    end
  end
end
