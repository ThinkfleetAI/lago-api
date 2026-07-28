# frozen_string_literal: true

# Per-entity payment providers (reseller "SaaS Mode"). A payment provider may
# optionally belong to a billing entity so an agency's own Stripe can collect
# for that entity's customers. NULL keeps the existing organization-level
# behaviour unchanged (all existing providers stay org-level).
class AddBillingEntityToPaymentProviders < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :payment_providers, :billing_entity, type: :uuid, null: true,
      index: {algorithm: :concurrently}
    add_foreign_key :payment_providers, :billing_entities, validate: false
  end
end
