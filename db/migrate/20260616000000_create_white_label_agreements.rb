# frozen_string_literal: true

class CreateWhiteLabelAgreements < ActiveRecord::Migration[8.0]
  def change
    create_table :white_label_agreements, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, foreign_key: true, type: :uuid

      t.string :plan_code, null: false
      t.string :msa_version, null: false
      t.string :terms_version, null: false
      t.string :status, null: false, default: "pending"

      # Subscription is created only AFTER the card is on file (see
      # WhiteLabel::ActivateService), so this is null until activation.
      t.string :subscription_external_id

      # Signature audit trail — what makes the click-accept legally defensible.
      t.datetime :accepted_at
      t.string :accepted_by_name
      t.string :accepted_by_title
      t.string :accepted_by_email
      t.string :accepted_ip
      t.string :accepted_user_agent

      t.timestamps
    end

    add_index :white_label_agreements, [:organization_id, :status]
    add_index :white_label_agreements, :customer_id, unique: true,
      name: "index_white_label_agreements_on_customer_unique",
      where: "status <> 'superseded'"
  end
end
