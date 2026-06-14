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

      def resolve(name:)
        result = ::Organizations::CreateService.call(
          name:,
          document_numbering: "per_organization"
        )
        return result_error(result) unless result.success?

        organization = result.organization

        ActiveRecord::Base.transaction do
          membership = Membership.create!(user: context[:current_user], organization:)
          MembershipRole.create!(organization:, membership:, role: Role.admins.first!)
        end

        organization
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
        result_error(result)
      end
    end
  end
end
