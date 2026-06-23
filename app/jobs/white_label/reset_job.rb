# frozen_string_literal: true

module WhiteLabel
  # Auto-reset a white-label agreement when its activation charge is declined.
  # Enqueued from Invoices::UpdateService the moment a `-wl` subscription invoice
  # transitions to `failed`. Idempotent: only acts on an `active` agreement, so a
  # retry / second failed-payment webhook is a no-op.
  class ResetJob < ApplicationJob
    queue_as :default

    def perform(invoice_id)
      invoice = Invoice.find_by(id: invoice_id)
      return unless invoice&.payment_failed?

      subscription_external_id = invoice.subscriptions.find { |s| s.external_id&.end_with?("-wl") }&.external_id
      return if subscription_external_id.blank?

      agreement = WhiteLabelAgreement.find_by(
        customer_id: invoice.customer_id,
        subscription_external_id:,
        status: "active"
      )
      return if agreement.nil?

      result = WhiteLabel::ResetService.call(agreement:, reason: "payment_declined")
      return unless result.success?

      WhiteLabelResetMailer
        .with(agreement:, signing_url: result.signing_url, recipient_email: result.recipient_email)
        .payment_declined
        .deliver_later

      notify_operator(agreement, "payment_declined")
    end

    private

    def notify_operator(agreement, reason)
      to = ENV["WHITE_LABEL_OPS_EMAIL"].presence ||
        agreement.customer.billing_entity&.email.presence ||
        agreement.organization.billing_entities.first&.email
      return if to.blank?

      WhiteLabelResetMailer.with(agreement:, reason:, to:).operator_notice.deliver_later
    end
  end
end
