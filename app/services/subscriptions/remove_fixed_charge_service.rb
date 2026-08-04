# frozen_string_literal: true

module Subscriptions
  class RemoveFixedChargeService < BaseService
    Result = BaseResult[:fixed_charge]

    # Detach an à-la-carte fixed charge from a single subscription. Only charges
    # that live on the subscription's *own* overridden plan may be removed — you
    # cannot delete a charge off the shared base plan through this path, since
    # that would affect every other subscriber. Not premium-gated (see
    # AddFixedChargeService).
    def initialize(subscription:, code:)
      @subscription = subscription
      @code = code

      super
    end

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription

      plan = subscription.plan

      # Guard: refuse to touch charges on a shared (non-override) plan.
      unless plan.parent_id
        return result.forbidden_failure!(code: "not_a_subscription_override")
      end

      fixed_charge = plan.fixed_charges.find_by(code: code)
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge

      destroy_result = FixedCharges::DestroyService.call(fixed_charge:, cascade_updates: false)
      destroy_result.raise_if_error!

      result.fixed_charge = destroy_result.fixed_charge
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :code
  end
end
