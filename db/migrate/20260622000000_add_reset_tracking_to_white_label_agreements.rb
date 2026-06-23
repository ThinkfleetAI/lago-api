# frozen_string_literal: true

# Tracks auto/manual resets of a white-label agreement after a declined payment.
# When the activation charge is declined we unwind the subscription + invoice and
# put the agreement back to `pending` so the signer can re-confirm with a new card
# (WhiteLabel::ResetService). These columns make that history visible to operators.
class AddResetTrackingToWhiteLabelAgreements < ActiveRecord::Migration[8.0]
  # Separate add_column statements (not a bulk change_table block) so
  # strong_migrations can verify each — adding a column with a constant default
  # is safe on Postgres 11+ (no table rewrite), and the other two are nullable.
  def change
    add_column :white_label_agreements, :reset_count, :integer, null: false, default: 0
    add_column :white_label_agreements, :last_reset_at, :datetime
    add_column :white_label_agreements, :last_reset_reason, :string
  end
end
