# frozen_string_literal: true

module Subscriptions
  class AddFixedChargeService < BaseService
    include Concerns::PlanOverrideConcern

    Result = BaseResult[:fixed_charge]

    # Attach a brand-new fixed charge (an à-la-carte add-on) to a single
    # subscription. Lago's stock API only lets you *override* fixed charges that
    # already exist on the shared plan; there is no way to add one to a lone
    # subscription. This service closes that gap: it ensures the subscription has
    # its own overridden plan, then creates the fixed charge on that override so
    # the base plan (and every other subscriber) is untouched.
    #
    # This is intentionally NOT premium-gated — self-serve à-la-carte add-ons are
    # the whole point (see feat/subscription-alacarte-addons).
    def initialize(subscription:, params:)
      @subscription = subscription
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription

      ActiveRecord::Base.transaction do
        target_plan = ensure_plan_override

        # Idempotency: if this add-on code is already attached to the override,
        # return it instead of failing on the unique (plan, code) constraint.
        existing = target_plan.fixed_charges.find_by(code: params[:code])
        if existing
          result.fixed_charge = existing
          return result
        end

        # CreateService emits fixed-charge events itself. Because ensure_plan_override
        # has already repointed this subscription at the override plan, that plan's
        # only subscriber is us — so CreateService's internal emit fires for exactly
        # this subscription (respecting apply_units_immediately). No extra emit here,
        # or events would be double-counted.
        create_result = FixedCharges::CreateService.call(
          plan: target_plan,
          params: params,
          cascade_updates: false
        )
        create_result.raise_if_error!

        result.fixed_charge = create_result.fixed_charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :params
  end
end
