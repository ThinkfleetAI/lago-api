# frozen_string_literal: true

# Adds a first-class `self_serve` flag to plans. When false, the plan is
# hidden from the customer-portal self-serve list (AvailablePlansResolver)
# but stays fully assignable by operators — used for contract-only tiers
# such as enterprise / white-label. Defaults true so every existing plan
# stays self-serve (non-breaking).
class AddSelfServeToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :self_serve, :boolean, default: true, null: false
  end
end
