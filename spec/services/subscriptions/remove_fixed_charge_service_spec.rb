# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::RemoveFixedChargeService do
  subject(:service) { described_class.new(subscription:, code:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:base_plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:code) { "extra_seat" }

  describe "#call" do
    before { subscription }

    context "when the charge lives on the subscription's own override plan" do
      let(:plan) { create(:plan, organization:, parent_id: base_plan.id) }
      let!(:fixed_charge) { create(:fixed_charge, plan:, organization:, add_on:, code:) }

      it "discards the fixed charge" do
        result = service.call

        expect(result).to be_success
        expect(fixed_charge.reload.discarded?).to be(true)
      end
    end

    context "when the subscription is on a shared (non-override) plan" do
      let(:plan) { base_plan }
      let!(:fixed_charge) { create(:fixed_charge, plan:, organization:, add_on:, code:) }

      it "refuses — you cannot strip a charge off a shared plan" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("not_a_subscription_override")
        expect(fixed_charge.reload.discarded?).to be(false)
      end
    end

    context "when no charge matches the code" do
      let(:plan) { create(:plan, organization:, parent_id: base_plan.id) }
      let(:code) { "does_not_exist" }

      it "returns a not-found failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end
  end
end
