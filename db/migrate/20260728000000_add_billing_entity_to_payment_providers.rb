# frozen_string_literal: true

# Per-entity payment providers (reseller "SaaS Mode"). A payment provider may
# optionally belong to a billing entity so an agency's own Stripe can collect
# for that entity's customers. NULL keeps the existing organization-level
# behaviour unchanged (all existing providers stay org-level).
class AddBillingEntityToPaymentProviders < ActiveRecord::Migration[8.0]
  def change
    add_reference :payment_providers,
      :billing_entity,
      type: :uuid,
      null: true,
      foreign_key: true,
      index: true
  end
end
