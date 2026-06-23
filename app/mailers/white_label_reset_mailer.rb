# frozen_string_literal: true

# Emails sent when a white-label agreement is reset after a declined payment
# (WhiteLabel::ResetService). `payment_declined` goes to the signer with a fresh
# link to re-confirm + add a working card; `operator_notice` tells the operator
# it happened so it never goes unnoticed.
class WhiteLabelResetMailer < ApplicationMailer
  def payment_declined
    @agreement = params[:agreement]
    @signing_url = params[:signing_url]
    @customer = @agreement.customer
    @billing_entity = billing_entity_for(@customer)
    @recipient = params[:recipient_email].presence || @agreement.notify_email

    return if @billing_entity.nil? || @billing_entity.email.blank?
    return if @recipient.blank?

    mail(
      to: @recipient,
      from: email_address_with_name(@billing_entity.from_email_address, @billing_entity.name),
      reply_to: email_address_with_name(@billing_entity.email, @billing_entity.name),
      subject: "Action needed: your payment didn’t go through — #{@billing_entity.name}"
    )
  end

  def operator_notice
    @agreement = params[:agreement]
    @customer = @agreement.customer
    @reason = params[:reason]
    @billing_entity = billing_entity_for(@customer)
    @recipient = params[:to].presence

    return if @recipient.blank? || @billing_entity.nil? || @billing_entity.email.blank?

    mail(
      to: @recipient,
      from: email_address_with_name(@billing_entity.from_email_address, @billing_entity.name),
      subject: "White-label agreement reset: #{@customer.name} (#{@reason})"
    )
  end

  private

  def billing_entity_for(customer)
    customer.billing_entity || customer.organization.billing_entities.first
  end
end
