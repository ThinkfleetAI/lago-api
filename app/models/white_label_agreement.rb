# frozen_string_literal: true

# A white-label / SDK customer's acceptance of the MSA + Terms.
#
# Lifecycle:
#   pending   -> created at provisioning; signed gate link emailed to the signer
#   accepted  -> signer clicked "I Accept"; signature audit trail recorded;
#                customer redirected to save a card. WhiteLabel::ActivateService
#                then creates the subscription once the card lands.
#   active    -> subscription created; recurring billing live
#
# The signed token in the gate link is minted with Lago's own MessageVerifier
# (SECRET_KEY_BASE) — same mechanism as the customer portal — so no extra auth
# infrastructure is needed and links self-expire.
#
# Each token also carries the agreement's current `token_nonce`. The nonce is
# rotated when the agreement is accepted and when it is reset, so a link only
# works for the state it was issued for: the emailed signing link stops working
# once the agreement is signed.
class WhiteLabelAgreement < ApplicationRecord
  STATUSES = %w[pending accepted active superseded].freeze
  TOKEN_PURPOSE = "white_label_agreement"
  TOKEN_TTL = 14.days

  belongs_to :organization
  belongs_to :customer

  validates :plan_code, :msa_version, :terms_version, presence: true
  validates :status, inclusion: {in: STATUSES}

  scope :pending, -> { where(status: "pending") }
  scope :awaiting_activation, -> { where(status: "accepted") }

  def self.verifier
    ActiveSupport::MessageVerifier.new(ENV.fetch("SECRET_KEY_BASE"))
  end

  # Find an agreement from a signed gate token; returns nil if the token is
  # invalid, expired, or was issued for a previous state of the agreement.
  def self.from_token(token)
    payload = verifier.verify(token, purpose: TOKEN_PURPOSE)
    id, nonce = Array(payload)
    agreement = find_by(id:)
    return nil if agreement.nil?

    valid = if nonce.nil?
      # Links issued before nonces existed carry only the id. They remain
      # usable for signing only, until the agreement first changes state.
      agreement.token_nonce.blank? && agreement.status == "pending"
    else
      agreement.token_nonce.present? &&
        ActiveSupport::SecurityUtils.secure_compare(agreement.token_nonce, nonce.to_s)
    end

    valid ? agreement : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def signed_token
    ensure_token_nonce!
    self.class.verifier.generate([id, token_nonce], purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
  end

  # Full URL of the hosted MSA acceptance gate for this agreement. Used by the
  # provisioning rake task (email link) and the customer portal (sign panel).
  def self.gate_base_url
    (ENV["WHITE_LABEL_GATE_URL"].presence || ENV["LAGO_API_URL"].presence ||
      ENV["LAGO_FRONT_URL"].presence || "http://localhost:3000").chomp("/")
  end

  # Link to sign the agreement. Only available while the agreement is pending:
  # once it is signed the signing link is no longer issued or accepted.
  def signing_url
    return nil unless status == "pending"

    gate_url
  end

  # Link that lets the signer resume the payment step of an accepted agreement
  # (used as the Stripe checkout cancel URL). Bound to the post-acceptance nonce.
  def payment_resume_url
    return nil unless status == "accepted"

    gate_url
  end

  def accept!(signer:, request_ip:, user_agent:)
    update!(
      status: "accepted",
      token_nonce: self.class.generate_token_nonce,
      accepted_at: Time.current,
      accepted_by_name: signer[:name],
      accepted_by_title: signer[:title],
      accepted_by_email: signer[:email],
      accepted_ip: request_ip,
      accepted_user_agent: user_agent
    )
  end

  # Put the agreement back to a clean signable state after a declined payment
  # (the subscription/invoice unwind itself lives in WhiteLabel::ResetService).
  # Clears the signature audit trail so the signer re-accepts on the fresh link,
  # and records why/when so operators can see the reset history.
  def reset_to_pending!(reason:)
    update!(
      status: "pending",
      token_nonce: self.class.generate_token_nonce,
      subscription_external_id: nil,
      accepted_at: nil,
      accepted_by_name: nil,
      accepted_by_title: nil,
      accepted_by_email: nil,
      accepted_ip: nil,
      accepted_user_agent: nil,
      reset_count: reset_count + 1,
      last_reset_at: Time.current,
      last_reset_reason: reason
    )
  end

  # Best email to reach the signer for a reset notice: whoever accepted, else the
  # customer of record.
  def notify_email
    accepted_by_email.presence || customer.email
  end

  def self.generate_token_nonce
    SecureRandom.urlsafe_base64(24)
  end

  private

  def gate_url
    "#{self.class.gate_base_url}/white-label/#{signed_token}"
  end

  def ensure_token_nonce!
    return if token_nonce.present?

    # Only set the nonce if nobody else did concurrently, then reload it so
    # every caller signs with the stored value.
    self.class.where(id:, token_nonce: nil).update_all(token_nonce: self.class.generate_token_nonce) # rubocop:disable Rails/SkipsModelValidations
    self.token_nonce = self.class.where(id:).pick(:token_nonce)
    clear_attribute_change(:token_nonce)
  end
end
