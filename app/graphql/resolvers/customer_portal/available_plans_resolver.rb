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

        plans = organization.plans.where(parent_id: nil).order(:amount_cents)
        plans = plans.where("code LIKE ?", "#{product_key}-%") if product_key.present?

        if exclude_current
          active_plan_codes = customer.subscriptions.active.joins(:plan).pluck("plans.code")
          plans = plans.where.not(code: active_plan_codes) if active_plan_codes.any?
        end

        plans
      end
    end
  end
end
