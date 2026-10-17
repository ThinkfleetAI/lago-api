# frozen_string_literal: true

module CustomerPortal
  # Single source of truth for which plans a customer-portal user may see
  # and subscribe to. Used by the `customerPortalAvailablePlans` resolver
  # and by the portal subscription mutations, so the list shown in the UI
  # and the plans accepted on the server always match.
  #
  # Rules:
  #   * top-level plans only (`parent_id: nil`)
  #   * `self_serve: true`
  #   * metadata `hidden_in_portal` is not "true"
  #   * when metadata `visible_to_products` is set, the customer must
  #     already have an active subscription in one of those products
  class AvailablePlansQuery
    def self.call(...)
      new(...).call
    end

    def self.find_plan(customer:, code:)
      new(customer:).find_plan(code)
    end

    def self.product_key_for(code)
      code.to_s.split("-").first
    end

    # SQL LIKE pattern matching subscriptions whose external_id ends with
    # `-<product_key>`, with wildcard characters escaped.
    def self.external_id_suffix_pattern(product_key)
      "%-#{ActiveRecord::Base.sanitize_sql_like(product_key.to_s)}"
    end

    def initialize(customer:, product_key: nil, exclude_current: false)
      @customer = customer
      @product_key = product_key
      @exclude_current = exclude_current
    end

    def call
      plans = base_scope.includes(:metadata).order(:amount_cents)

      if product_key.present?
        plans = plans.where("code LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(product_key)}-%")
      end

      if exclude_current
        active_plan_codes = active_subscription_plan_codes
        plans = plans.where.not(code: active_plan_codes) if active_plan_codes.any?
      end

      plans.to_a.select { |plan| visible?(plan) }
    end

    # Returns the plan with the given code if (and only if) it is available
    # to this customer, otherwise nil.
    def find_plan(code)
      return nil if code.blank?

      plan = base_scope.includes(:metadata).find_by(code:)
      return nil if plan.nil?

      visible?(plan) ? plan : nil
    end

    private

    attr_reader :customer, :product_key, :exclude_current

    def base_scope
      customer.organization.plans.where(parent_id: nil, self_serve: true)
    end

    def visible?(plan)
      meta = plan.metadata&.value || {}
      return false if meta["hidden_in_portal"].to_s == "true"

      allowed = meta["visible_to_products"].to_s.split(",").map(&:strip).reject(&:empty?)
      return true if allowed.empty?

      allowed.intersect?(customer_product_keys)
    end

    def active_subscription_plan_codes
      @active_subscription_plan_codes ||= customer.subscriptions.active.joins(:plan).pluck("plans.code")
    end

    def customer_product_keys
      @customer_product_keys ||= active_subscription_plan_codes.map { |c| self.class.product_key_for(c) }.uniq
    end
  end
end
