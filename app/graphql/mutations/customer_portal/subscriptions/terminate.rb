# frozen_string_literal: true

module Mutations
  module CustomerPortal
    module Subscriptions
      # Cancel a single subscription within a multi-product account.
      # The customer's other product subscriptions remain active.
      class Terminate < BaseMutation
        include AuthenticableCustomerPortalUser

        graphql_name "TerminateCustomerPortalSubscription"
        description "Cancel a single subscription belonging to the customer-portal user"

        argument :subscription_id, ID, required: true

        type Types::Subscriptions::Object

        def resolve(subscription_id:)
          customer = context[:customer_portal_user]
          subscription = customer.subscriptions.find(subscription_id)

          result = ::Subscriptions::TerminateService.call(subscription: subscription)
          result.success? ? result.subscription : result_error(result)
        rescue ActiveRecord::RecordNotFound
          execution_error(message: "subscription_not_found")
        end
      end
    end
  end
end
