# frozen_string_literal: true

module WhiteLabel
  # Creates the white-label subscription once the customer has a payment method
  # on file. Invoked from the Stripe `setup_intent.succeeded` webhook so the
  # pay-in-advance first invoice bills cleanly against a saved card (no race
  # between invoice generation and card entry), and every renewal auto-charges
  # off-session — "accept once, pay once, never log in."
  #
  # Idempotent: only acts on an `accepted` agreement, and flips it to `active`.
  class ActivateService < BaseService
    Result = BaseResult[:subscription, :white_label_agreement]

    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      agreement = WhiteLabelAgreement.awaiting_activation.find_by(customer_id: customer.id)
      return result if agreement.blank? # nothing to activate — not a WL customer, or already active

      plan = customer.organization.plans.find_by(code: agreement.plan_code)
      return result.not_found_failure!(resource: "plan") if plan.blank?

      external_id = "#{customer.external_id}-wl"

      sub_result = ::Subscriptions::CreateService.call(
        customer:,
        plan:,
        params: {
          external_id:,
          external_customer_id: customer.external_id,
          billing_time: "anniversary"
        }
      )
      return sub_result unless sub_result.success?

      agreement.update!(status: "active", subscription_external_id: external_id)

      result.subscription = sub_result.subscription
      result.white_label_agreement = agreement
      result
    end

    private

    attr_reader :customer
  end
end
