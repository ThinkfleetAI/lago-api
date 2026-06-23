# frozen_string_literal: true

module WhiteLabel
  # Unwinds a white-label agreement back to a clean, signable state after a
  # declined activation charge (or on operator request), so the signer can
  # re-confirm the MSA and add a working card on a fresh link.
  #
  # This is the single source of truth for the reset — both the automatic
  # decline handler (WhiteLabel::ResetJob) and the manual operator endpoint
  # (Api::V1::WhiteLabelController#reset) call it, so the behaviour can't drift.
  #
  # Steps (each best-effort/idempotent so a partial state still converges):
  #   1. void the WL subscription's open/failed invoices (no credit note — never paid)
  #   2. detach the declined card from the Stripe customer (so it can't be retried)
  #   3. terminate the WL subscription (skip credit note + final invoice)
  #   4. reset the agreement to `pending` + bump reset tracking
  #
  # Returns the recipient email + a freshly-minted signing link so the caller
  # can message the signer.
  class ResetService < BaseService
    include Customers::PaymentProviderFinder

    Result = BaseResult[:agreement, :signing_url, :recipient_email]

    def initialize(agreement:, reason:)
      @agreement = agreement
      @reason = reason
      super
    end

    def call
      return result.not_found_failure!(resource: "white_label_agreement") if agreement.nil?

      customer = agreement.customer
      # Capture the signer address before reset_to_pending! clears it.
      recipient_email = agreement.notify_email

      # Already clean — nothing to unwind, just hand back a fresh link.
      if agreement.status == "pending"
        result.agreement = agreement
        result.signing_url = agreement.signing_url
        result.recipient_email = recipient_email
        return result
      end

      subscription = find_wl_subscription(customer)

      if subscription
        void_open_invoices(subscription)
        detach_declined_card(customer, subscription)
        terminate_subscription(subscription)
      end

      agreement.reset_to_pending!(reason:)

      result.agreement = agreement
      result.signing_url = agreement.signing_url
      result.recipient_email = recipient_email
      result
    end

    private

    attr_reader :agreement, :reason

    def find_wl_subscription(customer)
      external_id = agreement.subscription_external_id.presence || "#{customer.external_id}-wl"
      customer.subscriptions.find_by(external_id:)
    end

    # Void any finalized, unpaid invoice on the WL subscription. No credit note:
    # the activation charge was declined, so nothing was ever paid.
    def void_open_invoices(subscription)
      subscription.invoices.where(status: :finalized).find_each do |invoice|
        next if invoice.voided? || invoice.payment_succeeded?

        Invoices::VoidService.call(invoice:, params: {generate_credit_note: false})
      end
    end

    def terminate_subscription(subscription)
      return if subscription.terminated?

      Subscriptions::TerminateService.call(
        subscription:,
        async: false,
        on_termination_credit_note: :skip,
        on_termination_invoice: :skip
      )
    end

    # Best-effort: pull the declined card off the Stripe customer so a re-attempt
    # can't silently retry the same bad card. Never blocks the reset.
    def detach_declined_card(customer, subscription)
      provider = payment_provider(customer)
      return if provider.nil? || provider.payment_type.to_s != "stripe"

      api_key = provider.secret_key
      return if api_key.blank?

      payment_method_id = declined_payment_method_id(customer, subscription, api_key)
      return if payment_method_id.blank?

      ::Stripe::PaymentMethod.detach(payment_method_id, {}, {api_key:})
    rescue => e
      Rails.logger.warn("[white-label] detach declined card failed for agreement #{agreement.id}: #{e.message}")
    end

    # Resolve the card that failed: prefer the payment method on the subscription's
    # latest payment intent; fall back to the Stripe customer's default card
    # (the one just added via the setup session).
    def declined_payment_method_id(customer, subscription, api_key)
      invoice_ids = subscription.invoices.where(status: :finalized).pluck(:id)
      payment = Payment
        .where(payable_type: "Invoice", payable_id: invoice_ids)
        .order(created_at: :desc).first

      if payment&.provider_payment_id.present?
        intent = ::Stripe::PaymentIntent.retrieve(payment.provider_payment_id, {api_key:})
        return intent.payment_method if intent.respond_to?(:payment_method) && intent.payment_method.present?
      end

      pc = payment_provider_customer(customer)
      return if pc&.provider_customer_id.blank?

      stripe_customer = ::Stripe::Customer.retrieve(pc.provider_customer_id, {api_key:})
      stripe_customer.dig("invoice_settings", "default_payment_method").presence ||
        stripe_customer["default_source"]
    rescue => e
      Rails.logger.warn("[white-label] resolve declined card failed for agreement #{agreement.id}: #{e.message}")
      nil
    end
  end
end
