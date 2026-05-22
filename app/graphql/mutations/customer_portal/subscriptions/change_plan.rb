# frozen_string_literal: true

module Mutations
  module CustomerPortal
    module Subscriptions
      # Switch an existing subscription to a different plan.
      # Used by the "Change Plan" flow in the customer portal.
      # Calls into Subscriptions::PlanUpgradeService which handles proration,
      # invoice generation, and Stripe billing automatically.
      class ChangePlan < BaseMutation
        include AuthenticableCustomerPortalUser

        graphql_name "ChangeCustomerPortalSubscriptionPlan"
        description "Switch a customer-portal subscription to a different plan"

        argument :subscription_id, ID, required: true,
          description: "The Lago subscription to switch (must belong to the authenticated portal user)"
        argument :plan_code, String, required: true,
          description: "Target plan code within the same organization"

        type Types::Subscriptions::Object

        def resolve(subscription_id:, plan_code:)
          customer = context[:customer_portal_user]
          current_subscription = customer.subscriptions.find(subscription_id)
          plan = customer.organization.plans.find_by!(code: plan_code, parent_id: nil)

          result = ::Subscriptions::PlanUpgradeService.call(
            current_subscription: current_subscription,
            plan: plan,
            params: {name: current_subscription.name}
          )

          result.success? ? result.subscription : result_error(result)
        rescue ActiveRecord::RecordNotFound
          execution_error(message: "subscription_not_found")
        end
      end
    end
  end
end
