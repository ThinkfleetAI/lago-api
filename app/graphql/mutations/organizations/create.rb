# frozen_string_literal: true

module Mutations
  module Organizations
    # Creates a brand-new organization and makes the current user its first
    # admin. Unlike most org mutations this does NOT `include RequiredOrganization`
    # — there is no current org yet; the logged-in user is the only requirement.
    #
    # Mirrors the org bootstrap performed by `Mutations::RegisterUser` /
    # `UsersService#register` (CreateService -> Membership -> admin MembershipRole)
    # so a self-serve "Create organization" button behaves exactly like signup.
    class Create < BaseMutation
      include AuthenticableApiUser

      graphql_name "CreateOrganization"
      description "Creates a new organization and adds the current user as an admin member"

      argument :name, String, required: true

      type Types::Organizations::CurrentOrganizationType

      DEFAULT_MAX_ORGANIZATIONS_PER_USER = 10

      def resolve(name:)
        user = context[:current_user]

        # Same gate as signup: when signup is disabled, only users who already
        # administer an organization may create additional ones.
        if signup_disabled? && !admin_memberships(user).exists?
          return not_allowed_error(code: "signup_disabled")
        end

        organization = nil
        limit_reached = false
        result = nil

        ActiveRecord::Base.transaction do
          # Serialize concurrent creations for the same user so the count
          # check below cannot be raced.
          user.lock!

          if admin_memberships(user).count >= max_organizations_per_user
            limit_reached = true
            raise ActiveRecord::Rollback
          end

          result = ::Organizations::CreateService.call(
            name:,
            document_numbering: "per_organization"
          )
          raise ActiveRecord::Rollback unless result.success?

          organization = result.organization
          membership = Membership.create!(user:, organization:)
          MembershipRole.create!(organization:, membership:, role: Role.admins.first!)
        end

        return forbidden_error(code: "organization_limit_reached") if limit_reached
        return result_error(result) unless result.success?

        organization
      rescue ActiveRecord::RecordInvalid => e
        result ||= BaseService::Result.new
        result.record_validation_failure!(record: e.record)
        result_error(result)
      end

      private

      def signup_disabled?
        ENV.fetch("LAGO_DISABLE_SIGNUP", "false") == "true"
      end

      def admin_memberships(user)
        user.memberships.active.admins
      end

      def max_organizations_per_user
        value = ENV.fetch("LAGO_MAX_ORGANIZATIONS_PER_USER", "").to_i
        value.positive? ? value : DEFAULT_MAX_ORGANIZATIONS_PER_USER
      end
    end
  end
end
