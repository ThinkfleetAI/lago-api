# frozen_string_literal: true

module Mutations
  module CustomerPortal
    module Subscriptions
      # Switch the active subscription within a product to a different plan.
      #
      # The product is derived from the target plan_code's prefix
      # (e.g. `aistack-business` → product `aistack`). The customer's active
      # subscription whose external_id ends with `-${product}` is the one
      # that gets switched.
      #
      # This avoids the stale-id problem: Lago's PlanUpgradeService creates
      # a new subscription record with a new lago_id on every plan change,
      # so a UI that hands back a stale id would fail. Looking up by
      # product key (derived from plan_code) is stable across switches.
      #
      # Each account has at most one active subscription per product by
      # convention, so this is unambiguous.
      class ChangePlan < BaseMutation
        include AuthenticableCustomerPortalUser

        graphql_name "ChangeCustomerPortalSubscriptionPlan"
        description "Switch the customer-portal user's active subscription within a product to a different plan"

        argument :plan_code, String, required: true,
          description: "Target plan code; product key (prefix before '-') determines which sub to switch"

        type Types::Subscriptions::Object

        def resolve(plan_code:)
          customer = context[:customer_portal_user]
          product_key = plan_code.split("-").first
          current_subscription = customer.subscriptions.active.find_by(
            "external_id LIKE ?", "%-#{product_key}"
          )
          return execution_error(message: "no_active_subscription_for_product") if current_subscription.nil?

          plan = customer.organization.plans.find_by!(code: plan_code, parent_id: nil)

          result = ::Subscriptions::PlanUpgradeService.call(
            current_subscription: current_subscription,
            plan: plan,
            params: {name: current_subscription.name}
          )

          result.success? ? result.subscription : result_error(result)
        rescue ActiveRecord::RecordNotFound
          execution_error(message: "plan_not_found")
        end
      end
    end
  end
end
