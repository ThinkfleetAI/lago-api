# frozen_string_literal: true

# Tracks auto/manual resets of a white-label agreement after a declined payment.
# When the activation charge is declined we unwind the subscription + invoice and
# put the agreement back to `pending` so the signer can re-confirm with a new card
# (WhiteLabel::ResetService). These columns make that history visible to operators.
class AddResetTrackingToWhiteLabelAgreements < ActiveRecord::Migration[8.0]
  def change
    change_table :white_label_agreements, bulk: true do |t|
      t.integer :reset_count, null: false, default: 0
      t.datetime :last_reset_at
      t.string :last_reset_reason
    end
  end
end
