# frozen_string_literal: true

# `white_label` is a new API key permission resource. Keys that currently
# hold full read/write access on every other resource are granted it too,
# so existing full-access keys keep working. Restricted keys are left as is.
class AddWhiteLabelToFullAccessApiKeys < ActiveRecord::Migration[8.0]
  PREVIOUS_RESOURCES = %w[
    activity_log add_on analytic api_log billable_metric coupon applied_coupon credit_note customer_usage
    customer event fee invoice organization payment payment_receipt payment_request payment_method plan subscription lifetime_usage
    tax wallet wallet_transaction webhook_endpoint webhook_jwt_public_key invoice_custom_section
    billing_entity alert feature security_log quote
  ].freeze

  def up
    full_access = PREVIOUS_RESOURCES.map do |resource|
      "COALESCE(permissions -> #{connection.quote(resource)}, '[]'::jsonb) @> '[\"read\", \"write\"]'::jsonb"
    end.join(" AND ")

    safety_assured do
      execute(<<~SQL.squish)
        UPDATE api_keys
        SET permissions = permissions || '{"white_label": ["read", "write"]}'::jsonb
        WHERE NOT (permissions ? 'white_label')
          AND #{full_access}
      SQL
    end
  end

  def down
    safety_assured do
      execute("UPDATE api_keys SET permissions = permissions - 'white_label' WHERE permissions ? 'white_label'")
    end
  end
end
