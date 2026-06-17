# frozen_string_literal: true

module WhiteLabel
  # Provisions a white-label / SDK customer: a Stripe-linked customer under the
  # `flobyte` billing entity + a pending MSA agreement. Returns the signing and
  # portal URLs. Shared by the flobyte:provision_whitelabel rake task and the
  # POST /api/v1/white_label/provision endpoint (called by the app's platform
  # admin, which resolves the platform owner email and passes it as external_id).
  class ProvisionService < BaseService
    Result = BaseResult[:agreement, :customer, :signing_url, :portal_url]

    BILLING_ENTITY_CODE = "flobyte"
    DEFAULT_PLAN_CODE = "aistack-whitelabel"
    MSA_VERSION = "v1"
    TERMS_VERSION = "v1"

    def initialize(organization:, external_id:, name:, email:, plan_code: nil)
      @organization = organization
      @external_id = external_id.to_s.strip
      @name = name
      @email = email
      @plan_code = plan_code.presence || DEFAULT_PLAN_CODE
      super
    end

    def call
      return result.single_validation_failure!(error_code: "missing_external_id") if external_id.blank?

      plan = organization.plans.find_by(code: plan_code)
      return result.not_found_failure!(resource: "plan") if plan.nil?

      stripe = organization.stripe_payment_providers.first
      return result.single_validation_failure!(error_code: "no_stripe_provider") if stripe.nil?

      customer = organization.customers.find_by(external_id:)
      unless customer
        create_result = ::Customers::CreateService.call(
          organization_id: organization.id,
          billing_entity_code: BILLING_ENTITY_CODE,
          external_id:, name:, email:, currency: "USD",
          payment_provider: "stripe", payment_provider_code: stripe.code,
          provider_customer: {sync_with_provider: true, sync: true}
        )
        return create_result unless create_result.success?
        customer = create_result.customer
      end

      agreement = WhiteLabelAgreement.where(customer_id: customer.id).where.not(status: "superseded").first
      agreement ||= WhiteLabelAgreement.create!(
        organization:, customer:, plan_code:,
        msa_version: MSA_VERSION, terms_version: TERMS_VERSION, status: "pending"
      )

      result.agreement = agreement
      result.customer = customer
      result.signing_url = agreement.signing_url
      result.portal_url = ::CustomerPortal::GenerateUrlService.call(customer:).url
      result
    end

    private

    attr_reader :organization, :external_id, :name, :email, :plan_code
  end
end
