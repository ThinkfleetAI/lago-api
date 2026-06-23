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

      # Operator list of white-label agreements for the current org, newest first.
      def index
        agreements = current_organization
          .white_label_agreements
          .where.not(status: "superseded")
          .includes(:customer)
          .order(created_at: :desc)

        render(json: {white_label_agreements: agreements.map { |a| serialize(a) }})
      end

      # Operator-triggered reset: unwind a declined agreement back to pending and
      # resend the signer a fresh link. Same path the auto handler uses.
      def reset
        agreement = current_organization.white_label_agreements.find_by(id: params[:id])
        return render_error_response(not_found_result("white_label_agreement")) if agreement.nil?

        result = ::WhiteLabel::ResetService.call(agreement:, reason: "manual_operator")
        return render_error_response(result) unless result.success?

        WhiteLabelResetMailer
          .with(agreement:, signing_url: result.signing_url, recipient_email: result.recipient_email)
          .payment_declined
          .deliver_later

        render(json: {white_label_agreement: serialize(agreement.reload), signing_url: result.signing_url})
      end

      private

      def serialize(agreement)
        customer = agreement.customer
        {
          lago_id: agreement.id,
          status: agreement.status,
          plan_code: agreement.plan_code,
          customer_name: customer.name,
          customer_email: customer.email,
          customer_external_id: customer.external_id,
          accepted_by_name: agreement.accepted_by_name,
          accepted_by_email: agreement.accepted_by_email,
          accepted_at: agreement.accepted_at,
          reset_count: agreement.reset_count,
          last_reset_at: agreement.last_reset_at,
          last_reset_reason: agreement.last_reset_reason,
          signing_url: agreement.signing_url,
          created_at: agreement.created_at
        }
      end

      def not_found_result(resource)
        BaseService::Result.new.not_found_failure!(resource:)
      end

      # Authentication (a valid org API key) is sufficient for this internal
      # endpoint; there is no per-resource API-key permission for white_label.
      def authorize
        true
      end
    end
  end
end
