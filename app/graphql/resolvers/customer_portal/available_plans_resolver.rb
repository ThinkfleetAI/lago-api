# frozen_string_literal: true

module Resolvers
  module CustomerPortal
    # Lists plans visible to the current customer-portal user, optionally
    # filtered to a single product via the `product_key` argument.
    #
    # Product key is extracted from the plan's `code` prefix: `aistack-*` →
    # "aistack", `growth-*` → "growth", etc. This matches the prefix
    # convention used by the parent app's bridge layer.
    #
    # When `exclude_current: true`, plans the customer is already subscribed
    # to are removed from the result (used by the "Add a Product" cross-sell).
    class AvailablePlansResolver < Resolvers::BaseResolver
      include AuthenticableCustomerPortalUser

      description "Lists plans available to the customer portal user, filtered by product"

      argument :product_key, String, required: false,
        description: "Filter to plans whose code starts with `${product_key}-`"
      argument :exclude_current, Boolean, required: false, default_value: false,
        description: "Omit plans the customer already has an active subscription to"

      type [Types::Plans::Object], null: false

      def resolve(product_key: nil, exclude_current: false)
        customer = context[:customer_portal_user]
        organization = customer.organization

        plans = organization.plans.where(parent_id: nil)
          .includes(:metadata)
          .order(:amount_cents)
        plans = plans.where("code LIKE ?", "#{product_key}-%") if product_key.present?

        if exclude_current
          active_plan_codes = customer.subscriptions.active.joins(:plan).pluck("plans.code")
          plans = plans.where.not(code: active_plan_codes) if active_plan_codes.any?
        end

        # Compute which products this customer already has — used for the
        # `visible_to_products` filter below.
        customer_product_keys = customer.subscriptions.active
          .joins(:plan).pluck("plans.code")
          .map { |c| c.split("-").first }.uniq

        plans.to_a.select do |plan|
          meta = plan.metadata&.value || {}
          # Hard-hide: any plan tagged hidden_in_portal=true never appears.
          next false if meta["hidden_in_portal"].to_s == "true"

          # Scoped visibility: if visible_to_products is set, customer must
          # already have an active sub in one of those products. If empty/absent,
          # plan is visible to all.
          allowed = meta["visible_to_products"].to_s.split(",").map(&:strip).reject(&:empty?)
          next true if allowed.empty?
          (allowed & customer_product_keys).any?
        end
      end
    end
  end
end
