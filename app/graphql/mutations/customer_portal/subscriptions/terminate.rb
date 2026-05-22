# frozen_string_literal: true

module Mutations
  module CustomerPortal
    module Subscriptions
      # Cancel the active subscription for a given product within a
      # multi-product account. The customer's other products remain
      # untouched. Looked up by `product_key` (same approach as ChangePlan)
      # for stable lookup across plan switches that create new sub records.
      class Terminate < BaseMutation
        include AuthenticableCustomerPortalUser

        graphql_name "TerminateCustomerPortalSubscription"
        description "Cancel the active subscription for a given product"

        argument :product_key, String, required: true,
          description: "Product to cancel (e.g. `aistack`, `growth`, `memory`)"

        type Types::Subscriptions::Object

        def resolve(product_key:)
          customer = context[:customer_portal_user]
          subscription = customer.subscriptions.active.find_by(
            "external_id LIKE ?", "%-#{product_key}"
          )
          return execution_error(message: "no_active_subscription_for_product") if subscription.nil?

          result = ::Subscriptions::TerminateService.call(subscription: subscription)
          result.success? ? result.subscription : result_error(result)
        end
      end
    end
  end
end
