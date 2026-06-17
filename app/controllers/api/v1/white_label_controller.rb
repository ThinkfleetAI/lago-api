# frozen_string_literal: true

module Api
  module V1
    # Internal provisioning endpoint for white-label / SDK customers, called by
    # the app's platform admin (which resolves the platform owner email and
    # passes it as external_id). Authenticated by the org's Lago API key.
    class WhiteLabelController < Api::BaseController
      def provision
        result = ::WhiteLabel::ProvisionService.call(
          organization: current_organization,
          external_id: params[:external_id],
          name: params[:name],
          email: params[:email],
          plan_code: params[:plan_code]
        )

        if result.success?
          render(json: {
            white_label_agreement: {
              lago_id: result.agreement.id,
              status: result.agreement.status,
              plan_code: result.agreement.plan_code,
              customer_external_id: result.customer.external_id,
              signing_url: result.signing_url,
              portal_url: result.portal_url
            }
          })
        else
          render_error_response(result)
        end
      end

      private

      # Authentication (a valid org API key) is sufficient for this internal
      # endpoint; there is no per-resource API-key permission for white_label.
      def authorize
        true
      end
    end
  end
end
