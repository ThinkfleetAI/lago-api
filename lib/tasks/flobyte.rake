# frozen_string_literal: true

# Flobyte (aistack) billing surface seeder.
#
# Idempotently provisions the Flobyte plan catalog — scoped to the focused
# product: Flows, Knowledge Base, Forms, Functions (+ SDK & white-label
# packaging) — plus the metric/feature/entitlement contract, for one
# organization. Customers are scoped to the `flobyte` billing entity; plans
# live at the org level.
#
# All constants + helpers live under the FlobyteCatalog module so they NEVER
# collide with other product seeders (thinkfleet_memory.rake etc.) — rake
# files share top-level scope, so a bare `PLANS =` / `def self.x` would clobber.
#
# Usage:
#   bin/rails 'flobyte:seed[<organization_id>]'
#   bin/rails 'flobyte:seed[<organization_id>,dry_run]'

module FlobyteCatalog
  BILLING_ENTITY_CODE = "flobyte"
  BILLING_ENTITY_NAME = "Flobyte"

  # Only the white-label plan meters usage (active flows). Standard tiers are
  # flat price + hard feature caps.
  METRICS = [
    {code: "active_flow", name: "Active flows", aggregation_type: :max_agg, field_name: "count"}
  ].freeze

  FEATURES = [
    {code: "aistack.flows", name: "Flows",
     privileges: [{code: "limit", name: "Active flow limit", value_type: "integer"}]},
    {code: "aistack.knowledge_base", name: "Knowledge Base",
     privileges: [{code: "limit", name: "KB document limit", value_type: "integer"}]},
    {code: "aistack.forms", name: "Forms",
     privileges: [{code: "limit", name: "Form limit", value_type: "integer"}]},
    {code: "aistack.functions", name: "Functions",
     privileges: [{code: "limit", name: "Function limit", value_type: "integer"}]},
    {code: "aistack.user_seats", name: "User seats",
     privileges: [{code: "limit", name: "Seat limit", value_type: "integer"}]},
    {code: "aistack.api_keys", name: "API keys (SDK)", privileges: []},
    {code: "aistack.embedding", name: "Embedding / SDK", privileges: []},
    {code: "aistack.white_label", name: "White-label", privileges: []}
  ].freeze

  STARTER = {"aistack.flows" => {"limit" => 5}, "aistack.knowledge_base" => {"limit" => 100},
             "aistack.user_seats" => {"limit" => 1}}.freeze
  BUSINESS = {"aistack.flows" => {"limit" => 50}, "aistack.knowledge_base" => {"limit" => 1_000},
              "aistack.forms" => {"limit" => 25}, "aistack.user_seats" => {"limit" => 5}}.freeze
  BUSINESS_PRO = {"aistack.flows" => {"limit" => 500}, "aistack.knowledge_base" => {"limit" => 10_000},
                  "aistack.forms" => {"limit" => 250}, "aistack.functions" => {"limit" => 100},
                  "aistack.api_keys" => {}, "aistack.embedding" => {}, "aistack.user_seats" => {"limit" => 20}}.freeze
  ENTERPRISE = {"aistack.flows" => {"limit" => 5_000}, "aistack.knowledge_base" => {"limit" => 50_000},
                "aistack.forms" => {}, "aistack.functions" => {}, "aistack.api_keys" => {},
                "aistack.embedding" => {}, "aistack.user_seats" => {"limit" => 1_000}}.freeze
  WHITELABEL = {"aistack.flows" => {}, "aistack.knowledge_base" => {}, "aistack.forms" => {},
                "aistack.functions" => {}, "aistack.api_keys" => {}, "aistack.embedding" => {},
                "aistack.white_label" => {}, "aistack.user_seats" => {}}.freeze

  PLANS = [
    {code: "aistack-starter", name: "Starter", description: "Flows + Knowledge Base.",
     amount_cents: 0, interval: :monthly, trial_period: 0, entitlements: STARTER},
    {code: "aistack-business", name: "Business", description: "Adds Forms.",
     amount_cents: 9_900, interval: :monthly, trial_period: 14, entitlements: BUSINESS},
    {code: "aistack-business-yearly", name: "Business (Yearly)", description: "Adds Forms.",
     amount_cents: 99_000, interval: :yearly, trial_period: 14, entitlements: BUSINESS},
    {code: "aistack-business-pro", name: "Business Pro", description: "Adds Functions + SDK.",
     amount_cents: 29_900, interval: :monthly, trial_period: 14, entitlements: BUSINESS_PRO},
    {code: "aistack-business-pro-yearly", name: "Business Pro (Yearly)", description: "Adds Functions + SDK.",
     amount_cents: 299_000, interval: :yearly, trial_period: 14, entitlements: BUSINESS_PRO},
    {code: "aistack-enterprise", name: "Enterprise", description: "Full scope at scale.",
     amount_cents: 300_000, interval: :monthly, trial_period: 0, entitlements: ENTERPRISE},
    {code: "aistack-enterprise-comp", name: "Enterprise (Comp $0)", description: "Internal/comped enterprise.",
     amount_cents: 0, interval: :monthly, trial_period: 0, entitlements: ENTERPRISE},
    {code: "aistack-whitelabel", name: "White-Label / SDK",
     description: "Reseller white-label license + active-flow usage.",
     amount_cents: 200_000, interval: :monthly, trial_period: 0, entitlements: WHITELABEL,
     charges: [
       {metric_code: "active_flow", charge_model: "graduated", properties: {
         graduated_ranges: [
           {from_value: 0, to_value: 200, flat_amount: "0", per_unit_amount: "0"},
           {from_value: 201, to_value: nil, flat_amount: "0", per_unit_amount: "5.00"}
         ]
       }}
     ]},
    {code: "aistack-whitelabel-test", name: "White-Label / SDK (Test $1)",
     description: "Internal end-to-end test of the white-label flow — $1/mo, no usage charges.",
     amount_cents: 100, interval: :monthly, trial_period: 0, entitlements: WHITELABEL}
  ].freeze

  def self.seed!(organization_id, dry_run:)
    organization = Organization.find(organization_id)
    puts "Seeding Flobyte in organization #{organization.id} (#{organization.name})  dry_run=#{dry_run}\n\n"
    ActiveRecord::Base.transaction do
      ensure_billing_entity!(organization, dry_run:)
      METRICS.each { |m| ensure_metric!(organization, m, dry_run:) }
      FEATURES.each { |f| ensure_feature!(organization, f, dry_run:) }
      PLANS.each { |p| ensure_plan!(organization, p, dry_run:) }
      raise ActiveRecord::Rollback if dry_run
    end
    puts "\n#{dry_run ? '[dry_run] no changes persisted' : '✓ done'}"
  end

  def self.ensure_billing_entity!(organization, dry_run:)
    existing = organization.billing_entities.find_by(code: BILLING_ENTITY_CODE)
    return existing if existing
    puts "+ billing entity '#{BILLING_ENTITY_CODE}'"
    return nil if dry_run
    organization.billing_entities.create!(code: BILLING_ENTITY_CODE, name: BILLING_ENTITY_NAME,
      default_currency: "USD", document_locale: organization.document_locale.presence || "en",
      timezone: organization.timezone.presence || "UTC")
  end

  def self.ensure_metric!(organization, spec, dry_run:)
    return puts("✓ metric '#{spec[:code]}'") if organization.billable_metrics.exists?(code: spec[:code])
    puts "+ metric '#{spec[:code]}'"
    return nil if dry_run
    organization.billable_metrics.create!(code: spec[:code], name: spec[:name],
      aggregation_type: spec[:aggregation_type], field_name: spec[:field_name])
  end

  def self.ensure_feature!(organization, spec, dry_run:)
    feature = organization.features.find_by(code: spec[:code])
    if feature
      puts "✓ feature '#{spec[:code]}'"
    else
      puts "+ feature '#{spec[:code]}'"
      return nil if dry_run
      feature = organization.features.create!(code: spec[:code], name: spec[:name])
    end
    spec[:privileges].each do |priv|
      next if feature.privileges.exists?(code: priv[:code])
      puts "  + privilege '#{spec[:code]}.#{priv[:code]}'"
      next if dry_run
      feature.privileges.create!(organization:, code: priv[:code], name: priv[:name], value_type: priv[:value_type])
    end
    feature
  end

  def self.ensure_plan!(organization, spec, dry_run:)
    plan = organization.plans.find_by(code: spec[:code])
    attrs = {name: spec[:name], description: spec[:description], amount_cents: spec[:amount_cents],
             interval: spec[:interval], trial_period: spec[:trial_period], amount_currency: "USD"}
    if plan
      puts "~ plan '#{spec[:code]}'"
      plan.update!(**attrs) unless dry_run
    else
      puts "+ plan '#{spec[:code]}'"
      return nil if dry_run
      plan = organization.plans.create!(code: spec[:code], pay_in_advance: true, **attrs)
    end
    reset_charges!(organization, plan, spec[:charges] || [], dry_run:)
    apply_entitlements!(organization, plan, spec[:entitlements], dry_run:)
    plan
  end

  # Reset a plan's charges to exactly the spec (so re-scoping pricing is safe).
  def self.reset_charges!(organization, plan, charge_specs, dry_run:)
    return if dry_run
    plan.charges.destroy_all
    charge_specs.each do |c|
      metric = organization.billable_metrics.find_by!(code: c[:metric_code])
      plan.charges.create!(organization:, billable_metric: metric,
        code: c[:metric_code], charge_model: c[:charge_model],
        pay_in_advance: false, invoiceable: true, prorated: false,
        min_amount_cents: 0, properties: c[:properties])
      puts "  + charge on '#{c[:metric_code]}' (#{c[:charge_model]})"
    end
  end

  # ---------------------------------------------------------------------------
  # White-label / SDK customer provisioning.
  #
  # Creates a Stripe-linked customer under the `flobyte` billing entity and a
  # PENDING agreement, then prints the signed MSA gate link to email the signer.
  # The subscription is NOT created here — it is created after the signer accepts
  # the MSA and saves a card (WhiteLabel::ActivateService, via Stripe webhook).
  # ---------------------------------------------------------------------------
  WHITELABEL_PLAN_CODE = "aistack-whitelabel"
  MSA_VERSION = "v1"
  TERMS_VERSION = "v1"

  def self.provision_whitelabel!(organization_id:, external_id:, name:, email:, plan_code: WHITELABEL_PLAN_CODE)
    organization = Organization.find(organization_id)

    plan = organization.plans.find_by(code: plan_code)
    abort "Plan '#{plan_code}' not found — run flobyte:seed[#{organization_id}] first" if plan.nil?

    stripe = organization.stripe_payment_providers.first
    abort "No Stripe payment provider on organization #{organization_id} — connect Stripe before provisioning" if stripe.nil?

    customer = organization.customers.find_by(external_id:)
    if customer
      puts "✓ customer '#{external_id}' already exists (#{customer.id})"
    else
      result = ::Customers::CreateService.call(
        organization_id: organization.id,
        billing_entity_code: FlobyteCatalog::BILLING_ENTITY_CODE,
        external_id:,
        name:,
        email:,
        currency: "USD",
        payment_provider: "stripe",
        payment_provider_code: stripe.code,
        # Eagerly create the Stripe customer (sync) so the acceptance gate can
        # generate a checkout URL immediately — without this, Lago only records
        # *which* provider to use and never creates the Stripe customer.
        provider_customer: {sync_with_provider: true, sync: true}
      )
      result.raise_if_error!
      customer = result.customer
      puts "+ customer '#{external_id}' (#{customer.id}) under '#{FlobyteCatalog::BILLING_ENTITY_CODE}', Stripe-linked"
    end

    agreement = WhiteLabelAgreement.where(customer_id: customer.id)
      .where.not(status: "superseded").first
    if agreement
      puts "✓ agreement already exists (status: #{agreement.status})"
    else
      agreement = WhiteLabelAgreement.create!(
        organization:, customer:, plan_code:,
        msa_version: MSA_VERSION, terms_version: TERMS_VERSION, status: "pending"
      )
      puts "+ pending agreement #{agreement.id}"
    end

    link = agreement.signing_url
    puts "\nEmail this acceptance link to #{name} <#{email}> (valid #{WhiteLabelAgreement::TOKEN_TTL.inspect}):\n\n  #{link}\n"
    link
  end

  def self.apply_entitlements!(organization, plan, spec, dry_run:)
    spec.each do |feature_code, privilege_values|
      feature = organization.features.find_by(code: feature_code)
      next warn("  ! feature '#{feature_code}' missing") unless feature
      entitlement = plan.entitlements.find_by(entitlement_feature_id: feature.id)
      unless entitlement
        puts "  + entitle '#{plan.code}' → '#{feature_code}'"
        next if dry_run
        entitlement = Entitlement::Entitlement.create!(organization:, plan:, feature:)
      end
      next if dry_run
      privilege_values.each do |priv_code, value|
        privilege = feature.privileges.find_by(code: priv_code)
        next warn("  ! privilege '#{feature_code}.#{priv_code}' missing") unless privilege
        coerced = value.to_s
        existing = entitlement.values.find_by(entitlement_privilege_id: privilege.id)
        if existing
          existing.update!(value: coerced) unless existing.value == coerced
        else
          Entitlement::EntitlementValue.create!(organization:, entitlement:, privilege:, value: coerced)
        end
      end
    end
  end
end

namespace :flobyte do
  desc "Seed Flobyte (aistack) plans + entitlements for one organization"
  task :seed, %i[organization_id mode] => :environment do |_task, args|
    abort "Missing organization_id. Usage: bin/rails 'flobyte:seed[<org_id>]'" unless args[:organization_id]
    FlobyteCatalog.seed!(args[:organization_id], dry_run: args[:mode].to_s == "dry_run")
  end

  desc "Provision a white-label/SDK customer (Stripe-linked) + pending MSA gate link. Optional 5th arg = plan_code (default aistack-whitelabel; use aistack-whitelabel-test for a $1 dry run)"
  task :provision_whitelabel, %i[organization_id external_id name email plan_code] => :environment do |_task, args|
    %i[organization_id external_id name email].each do |k|
      abort "Missing #{k}. Usage: bin/rails 'flobyte:provision_whitelabel[<org_id>,<external_id>,<name>,<email>,<plan_code?>]'" if args[k].blank?
    end
    FlobyteCatalog.provision_whitelabel!(
      organization_id: args[:organization_id], external_id: args[:external_id],
      name: args[:name], email: args[:email],
      plan_code: args[:plan_code].presence || FlobyteCatalog::WHITELABEL_PLAN_CODE
    )
  end
end
