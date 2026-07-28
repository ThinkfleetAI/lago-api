# frozen_string_literal: true

module PaymentProviders
  class FindService < BaseService
    attr_reader :id, :code, :organization_id, :payment_provider_type, :billing_entity_id, :scope

    def initialize(organization_id:, code: nil, id: nil, payment_provider_type: nil, billing_entity_id: nil)
      @id = id
      @code = code
      @organization_id = organization_id
      @payment_provider_type = payment_provider_type
      @billing_entity_id = billing_entity_id
      @scope = PaymentProviders::BaseProvider.where(organization_id:)

      if payment_provider_type.present?
        @scope = @scope.where(type: "PaymentProviders::#{payment_provider_type.classify}Provider")
      end

      super(nil)
    end

    def call
      if id.present? && (payment_provider = scope.find_by(id:))
        result.payment_provider = payment_provider
        return result
      end

      # Prefer a provider scoped to the caller's billing entity (e.g. an agency's
      # own Stripe); fall back to the org-level providers when none exists so
      # existing single-Stripe setups are unaffected. When no billing entity is
      # given (webhooks, management APIs) the scope is left untouched.
      apply_billing_entity_scope!

      if code.blank? && scope.count > 1
        return result.service_failure!(
          code: "payment_provider_code_missing",
          message: "Payment provider code is missing"
        )
      end

      @scope = scope.where(code:) if code.present?

      unless scope.exists?
        return result.service_failure!(code: "payment_provider_not_found", message: "Payment provider not found")
      end

      result.payment_provider = scope.first
      result
    end

    private

    def apply_billing_entity_scope!
      return if billing_entity_id.blank?

      entity_scoped = scope.where(billing_entity_id:)
      @scope = entity_scoped if entity_scoped.exists?
    end
  end
end
