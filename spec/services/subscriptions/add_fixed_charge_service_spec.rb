# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::AddFixedChargeService do
  subject(:service) { described_class.new(subscription:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:params) do
    {
      add_on_code: add_on.code,
      code: "extra_seat",
      charge_model: "standard",
      units: "1"
    }
  end

  describe "#call" do
    before { subscription }

    # The whole point of Option B: à-la-carte add-ons work on the open-core
    # license, without a premium key.
    context "without premium license" do
      it "clones the plan into a per-subscription override" do
        expect { service.call }.to change(Plan, :count).by(1)

        new_plan = subscription.reload.plan
        expect(new_plan.parent_id).to eq(plan.id)
      end

      it "creates the fixed charge on the override plan" do
        result = service.call

        expect(result).to be_success
        expect(result.fixed_charge.code).to eq("extra_seat")
        expect(result.fixed_charge.plan.parent_id).to eq(plan.id)
        expect(result.fixed_charge.add_on_id).to eq(add_on.id)
      end

      it "leaves the shared base plan untouched" do
        expect { service.call }.not_to change { plan.reload.fixed_charges.count }
      end

      it "is idempotent on the add-on code" do
        service.call
        expect { described_class.new(subscription: subscription.reload, params:).call }
          .not_to change(FixedCharge, :count)
      end
    end

    context "when the subscription is missing" do
      subject(:service) { described_class.new(subscription: nil, params:) }

      it "returns a not-found failure" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end
  end
end
