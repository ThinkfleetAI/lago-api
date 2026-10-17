# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Organizations::Create do
  subject(:result) do
    execute_graphql(
      current_user: user,
      query: mutation,
      variables: {input: {name: "New Org"}}
    )
  end

  let(:user) { create(:user) }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateOrganizationInput!) {
        createOrganization(input: $input) { id name }
      }
    GQL
  end

  around do |example|
    keys = %w[LAGO_DISABLE_SIGNUP LAGO_MAX_ORGANIZATIONS_PER_USER]
    previous = keys.index_with { |k| ENV[k] }
    example.run
  ensure
    previous.each { |k, v| ENV[k] = v }
  end

  before { create(:role, :admin) }

  it_behaves_like "requires current user"

  it "creates an organization with the user as admin" do
    expect { result }.to change(Organization, :count).by(1)

    organization = Organization.find(result["data"]["createOrganization"]["id"])
    expect(organization.name).to eq("New Org")
    expect(user.memberships.active.admins.where(organization:)).to exist
  end

  context "when signup is disabled" do
    before { ENV["LAGO_DISABLE_SIGNUP"] = "true" }

    context "when the user is not admin of any organization" do
      before { create(:membership, user:) }

      it "is not allowed" do
        expect { result }.not_to change(Organization, :count)
        expect_graphql_error(result:, message: "signup_disabled")
      end
    end

    context "when the user is admin of an organization" do
      before { create(:membership, user:, roles: [:admin]) }

      it "creates the organization" do
        expect { result }.to change(Organization, :count).by(1)
      end
    end
  end

  context "when the user reached the organization limit" do
    before do
      ENV["LAGO_MAX_ORGANIZATIONS_PER_USER"] = "2"
      create_list(:membership, 2, user:, roles: [:admin])
    end

    it "is forbidden" do
      expect { result }.not_to change(Organization, :count)
      expect_graphql_error(result:, message: "organization_limit_reached")
    end
  end
end
