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

  # Find an agreement from a signed gate token; returns nil if invalid/expired.
  def self.from_token(token)
    id = verifier.verify(token, purpose: TOKEN_PURPOSE)
    find_by(id:)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def signed_token
    self.class.verifier.generate(id, purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
  end

  def accept!(signer:, request_ip:, user_agent:)
    update!(
      status: "accepted",
      accepted_at: Time.current,
      accepted_by_name: signer[:name],
      accepted_by_title: signer[:title],
      accepted_by_email: signer[:email],
      accepted_ip: request_ip,
      accepted_user_agent: user_agent
    )
  end
end
