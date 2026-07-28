# frozen_string_literal: true

module Types
  module PaymentProviders
    class StripeInput < BaseInputObject
      description "Stripe input arguments"

      argument :code, String, required: true
      argument :name, String, required: true
      argument :secret_key, String, required: false
      argument :success_redirect_url, String, required: false
      argument :supports_3ds, Boolean, required: false
      # Optional: scope this Stripe provider to a billing entity (reseller's own
      # Stripe). Only applied on creation; omit for an org-level provider.
      argument :billing_entity_code, String, required: false
      # Optional: Stripe Connect connected account (acct_…) — the reseller's own
      # Stripe. When set, secret_key is the platform key and calls run on that
      # connected account.
      argument :connected_account_id, String, required: false
    end
  end
end
