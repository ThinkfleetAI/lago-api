# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerPortal::AvailablePlansQuery do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:basic) { create(:plan, organization:, code: "aistack-basic", amount_cents: 100) }
  let(:pro) { create(:plan, organization:, code: "aistack-pro", amount_cents: 200) }
  let(:enterprise) { create(:plan, organization:, code: "aistack-enterprise", self_serve: false) }
  let(:hidden) { create(:plan, organization:, code: "aistack-hidden") }
  let(:addon) { create(:plan, organization:, code: "growth-addon") }
  let(:child) { create(:plan, organization:, code: "aistack-child", parent: basic) }
  let(:other_org_plan) { create(:plan, code: "aistack-other") }

  before do
    create(:item_metadata, organization:, owner: hidden, value: {"hidden_in_portal" => "true"})
    create(:item_metadata, organization:, owner: addon, value: {"visible_to_products" => "memory, aistack"})
    [basic, pro, enterprise, hidden, addon, child, other_org_plan]
  end

  describe ".call" do
    it "returns only self-serve, visible, top-level plans of the organization" do
      expect(described_class.call(customer:)).to eq([basic, pro])
    end

    context "when the customer has a subscription in a product listed in visible_to_products" do
      before { create(:subscription, customer:, plan: basic, external_id: "#{customer.external_id}-aistack") }

      it "includes the scoped plan" do
        expect(described_class.call(customer:)).to contain_exactly(basic, pro, addon)
      end

      it "excludes current plans when requested" do
        expect(described_class.call(customer:, exclude_current: true)).to contain_exactly(pro, addon)
      end
    end

    it "filters by product key" do
      expect(described_class.call(customer:, product_key: "growth")).to eq([])
      expect(described_class.call(customer:, product_key: "aistack")).to eq([basic, pro])
    end

    it "treats LIKE wildcards in the product key literally" do
      expect(described_class.call(customer:, product_key: "%")).to eq([])
      expect(described_class.call(customer:, product_key: "aistac_")).to eq([])
    end
  end

  describe ".find_plan" do
    it "returns an available plan" do
      expect(described_class.find_plan(customer:, code: "aistack-pro")).to eq(pro)
    end

    it "returns nil for plans that are not offered in the portal" do
      %w[aistack-enterprise aistack-hidden growth-addon aistack-child aistack-other unknown].each do |code|
        expect(described_class.find_plan(customer:, code:)).to be_nil, "expected #{code} to be unavailable"
      end
    end
  end

  describe ".external_id_suffix_pattern" do
    it "escapes LIKE wildcards" do
      expect(described_class.external_id_suffix_pattern("a%b_c")).to eq("%-a\\%b\\_c")
    end
  end
end
