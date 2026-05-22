# frozen_string_literal: true

module Mutations
  module CustomerPortal
    module Subscriptions
      # Add a NEW subscription (e.g. customer adds Growth OS to an account
      # that previously only had AI Stack). External_id follows the parent
      # app's bridge convention: `${customer.external_id}-${productKey}`
      # where productKey is derived from the plan code's prefix.
      class Create < BaseMutation
        include AuthenticableCustomerPortalUser

        graphql_name "CreateCustomerPortalSubscription"
        description "Add a new product subscription for the customer-portal user"

        argument :plan_code, String, required: true,
          description: "Plan code to subscribe to (must be visible to this customer's organization)"

        type Types::Subscriptions::Object

        def resolve(plan_code:)
          customer = context[:customer_portal_user]
          plan = customer.organization.plans.find_by!(code: plan_code, parent_id: nil)
          product_key = plan_code.split("-").first
          external_id = "#{customer.external_id}-#{product_key}"

          result = ::Subscriptions::CreateService.call(
            customer: customer,
            plan: plan,
            params: {
              name: nil,
              external_id: external_id,
              external_customer_id: customer.external_id,
              billing_time: "calendar"
            }
          )

          result.success? ? result.subscription : result_error(result)
        rescue ActiveRecord::RecordNotFound
          execution_error(message: "plan_not_found")
        end
      end
    end
  end
end
