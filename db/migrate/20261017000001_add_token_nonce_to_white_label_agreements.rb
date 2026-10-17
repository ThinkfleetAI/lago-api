# frozen_string_literal: true

# Gate links embed the agreement's token_nonce, which is rotated on acceptance
# and reset so a link is only valid for the state it was issued for.
class AddTokenNonceToWhiteLabelAgreements < ActiveRecord::Migration[8.0]
  def change
    add_column :white_label_agreements, :token_nonce, :string
  end
end
