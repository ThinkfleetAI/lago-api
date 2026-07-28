# frozen_string_literal: true

module Api
  module V1
    module PaymentProviders
      # Registers a reseller's Stripe Connect account (acct_…) as an
      # entity-scoped Stripe payment provider, so the agency's sub-account
      # retail invoices collect on the agency's OWN connected account.
      #
      # Server-to-server (api_key auth). The connected provider reuses the
      # organization's platform Stripe key — calls run on the connected account
      # via the Stripe-Account header (see PaymentProviders::StripeProvider).
      # Idempotent by provider code.
      class StripeConnectController < Api::BaseController
        def create
          platform_provider = current_organization.stripe_payment_providers
            .where(billing_entity_id: nil).first
          return not_found_error(resource: "stripe_payment_provider") if platform_provider.blank?

          result = ::PaymentProviders::StripeService.new.create_or_update(
            organization_id: current_organization.id,
            code: create_params[:code],
            name: create_params[:name],
            secret_key: platform_provider.secret_key,
            billing_entity_code: create_params[:billing_entity_code],
            connected_account_id: create_params[:connected_account_id]
          )

          if result.success?
            render(json: {payment_provider: {lago_id: result.stripe_provider.id, code: result.stripe_provider.code}})
          else
            render_error_response(result)
          end
        end

        private

        def create_params
          params.require(:payment_provider).permit(:code, :name, :billing_entity_code, :connected_account_id)
        end
      end
    end
  end
end
