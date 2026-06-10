# frozen_string_literal: true

# ThinkFleet Memory billing surface seeder.
#
# Idempotently provisions the four Memory plans (Dev / Team / Business /
# Enterprise) plus their billable metrics, features, and entitlements for the
# given organization. Mirrors the EngageIt isolation pattern: customers are
# scoped to the `thinkfleet-memory` billing entity, while the plans themselves
# live at the organization level (Lago plans don't carry a billing_entity_id).
#
# The product API at memory.thinkfleet.ai (memory-thinkfleet repo) reads these
# entitlements via /plans/<code>/entitlements at request time. Feature codes
# and privilege codes are the contract — they MUST match the constants in
# packages/server/api/src/app/chatbot/agent-memory/billing/memory-entitlements.ts
# on the consumer side.
#
# Usage:
#   bin/rails 'thinkfleet_memory:seed[<organization_id>]'
#   bin/rails 'thinkfleet_memory:seed[<organization_id>,dry_run]'
#
# Idempotency: every create is `find_or_create_by!` keyed by `code`. Re-running
# after success is a no-op. Run with `dry_run` second arg to print intended
# actions without persisting.
#
# Re-applying entitlement values: existing entitlement values for the same
# (entitlement, privilege) pair are UPDATED (not duplicated). Run again to
# bump quotas without touching customer subscriptions.

namespace :thinkfleet_memory do
  BILLING_ENTITY_CODE = "thinkfleet-memory"
  BILLING_ENTITY_NAME = "ThinkFleet Memory"

  METRICS = [
    {code: "memory.events_ingested.used", name: "Memory events ingested",
     aggregation_type: :sum_agg, field_name: "amount"},
    {code: "memory.predictions.used", name: "Memory predictions",
     aggregation_type: :sum_agg, field_name: "amount"}
  ].freeze

  # Each feature declares the privilege CATALOG it can carry. Plans fill in
  # concrete values per (feature, privilege).
  FEATURES = [
    {code: "memory.subjects", name: "Memory subjects",
     privileges: [{code: "limit", name: "Subject limit", value_type: "integer"}]},
    {code: "memory.active_triggers", name: "Active triggers",
     privileges: [{code: "limit", name: "Active trigger limit", value_type: "integer"}]},
    {code: "memory.events_ingested", name: "Events ingested per month",
     privileges: [{code: "included_monthly", name: "Included monthly events", value_type: "integer"}]},
    {code: "memory.predictions", name: "Predictions per month",
     privileges: [{code: "included_monthly", name: "Included monthly predictions", value_type: "integer"}]},
    {code: "memory.health_vertical", name: "Health vertical estimator", privileges: []},
    {code: "memory.finance_vertical", name: "Finance vertical estimator", privileges: []},
    {code: "memory.on_device", name: "On-device deployment", privileges: []},
    {code: "memory.vpc_deployment", name: "VPC deployment", privileges: []},
    {code: "memory.audit_retention", name: "Audit log retention",
     privileges: [{code: "retention_days", name: "Retention days", value_type: "integer"}]}
  ].freeze

  # Plan entitlements: feature_code => { privilege_code => value, ... }
  # Empty hash = feature attached, no privilege value (boolean / unlimited).
  PLANS = [
    {
      code: "memory-dev",
      name: "Memory Dev",
      description: "Free tier — integrate the SDK, prove the value.",
      amount_cents: 0,
      interval: :monthly,
      trial_period: 0,
      entitlements: {
        "memory.subjects" => {"limit" => 500},
        "memory.active_triggers" => {"limit" => 3},
        "memory.events_ingested" => {"included_monthly" => 10_000},
        "memory.predictions" => {"included_monthly" => 1_000},
        "memory.audit_retention" => {"retention_days" => 30}
      }
    },
    {
      code: "memory-team",
      name: "Memory Team",
      description: "For small ops teams running one workflow in production.",
      amount_cents: 19_900,
      interval: :monthly,
      trial_period: 14,
      entitlements: {
        "memory.subjects" => {"limit" => 10_000},
        "memory.active_triggers" => {},
        "memory.events_ingested" => {"included_monthly" => 250_000},
        "memory.predictions" => {"included_monthly" => 25_000},
        "memory.audit_retention" => {"retention_days" => 90}
      }
    },
    {
      code: "memory-business",
      name: "Memory Business",
      description: "Production-grade memory + one vertical estimator + VPC option.",
      amount_cents: 149_900,
      interval: :monthly,
      trial_period: 14,
      entitlements: {
        "memory.subjects" => {"limit" => 100_000},
        "memory.active_triggers" => {},
        "memory.events_ingested" => {"included_monthly" => 5_000_000},
        "memory.predictions" => {"included_monthly" => 500_000},
        "memory.audit_retention" => {"retention_days" => 365},
        "memory.vpc_deployment" => {},
        "memory.health_vertical" => {}
      }
    },
    {
      code: "memory-enterprise",
      name: "Memory Enterprise",
      description: "Unlimited scale, all verticals, on-device, 7-year audit, custom SLA.",
      amount_cents: 0,
      interval: :monthly,
      trial_period: 0,
      entitlements: {
        "memory.subjects" => {},
        "memory.active_triggers" => {},
        "memory.events_ingested" => {},
        "memory.predictions" => {},
        "memory.audit_retention" => {"retention_days" => 2555},
        "memory.vpc_deployment" => {},
        "memory.on_device" => {},
        "memory.health_vertical" => {},
        "memory.finance_vertical" => {}
      }
    }
  ].freeze

  desc "Seed ThinkFleet Memory plans + entitlements for one organization"
  task :seed, %i[organization_id mode] => :environment do |_task, args|
    organization_id = args[:organization_id]
    dry_run = args[:mode].to_s == "dry_run"

    abort <<~MSG unless organization_id
      Missing organization_id argument.

      Usage:
        bin/rails 'thinkfleet_memory:seed[<organization_id>]'
        bin/rails 'thinkfleet_memory:seed[<organization_id>,dry_run]'
    MSG

    organization = Organization.find(organization_id)
    puts "Seeding ThinkFleet Memory in organization #{organization.id} (#{organization.name})"
    puts "  dry_run: #{dry_run}"
    puts ""

    ActiveRecord::Base.transaction do
      ensure_billing_entity!(organization, dry_run:)
      METRICS.each { |m| ensure_metric!(organization, m, dry_run:) }
      FEATURES.each { |f| ensure_feature!(organization, f, dry_run:) }
      PLANS.each { |p| ensure_plan!(organization, p, dry_run:) }
      raise ActiveRecord::Rollback if dry_run
    end

    puts ""
    puts dry_run ? "[dry_run] no changes persisted" : "✓ done"
  end

  def self.ensure_billing_entity!(organization, dry_run:)
    existing = organization.billing_entities.find_by(code: BILLING_ENTITY_CODE)
    if existing
      puts "✓ billing entity '#{BILLING_ENTITY_CODE}' already exists"
      return existing
    end
    puts "+ creating billing entity '#{BILLING_ENTITY_CODE}'"
    return nil if dry_run
    organization.billing_entities.create!(
      code: BILLING_ENTITY_CODE,
      name: BILLING_ENTITY_NAME,
      default_currency: "USD",
      document_locale: organization.document_locale.presence || "en",
      timezone: organization.timezone.presence || "UTC"
    )
  end

  def self.ensure_metric!(organization, spec, dry_run:)
    existing = organization.billable_metrics.where(code: spec[:code]).first
    if existing
      puts "✓ metric '#{spec[:code]}' already exists"
      return existing
    end
    puts "+ creating metric '#{spec[:code]}'"
    return nil if dry_run
    organization.billable_metrics.create!(
      code: spec[:code],
      name: spec[:name],
      aggregation_type: spec[:aggregation_type],
      field_name: spec[:field_name]
    )
  end

  def self.ensure_feature!(organization, spec, dry_run:)
    feature = organization.features.find_by(code: spec[:code])
    if feature
      puts "✓ feature '#{spec[:code]}' already exists"
    else
      puts "+ creating feature '#{spec[:code]}'"
      return nil if dry_run
      feature = organization.features.create!(
        code: spec[:code],
        name: spec[:name]
      )
    end

    spec[:privileges].each do |priv_spec|
      existing_priv = feature.privileges.find_by(code: priv_spec[:code])
      if existing_priv
        puts "  ✓ privilege '#{spec[:code]}.#{priv_spec[:code]}' already exists"
      else
        puts "  + creating privilege '#{spec[:code]}.#{priv_spec[:code]}'"
        next if dry_run
        feature.privileges.create!(
          organization: organization,
          code: priv_spec[:code],
          name: priv_spec[:name],
          value_type: priv_spec[:value_type]
        )
      end
    end
    feature
  end

  def self.ensure_plan!(organization, spec, dry_run:)
    plan = organization.plans.find_by(code: spec[:code])
    if plan
      puts "~ plan '#{spec[:code]}' exists; updating metadata"
      unless dry_run
        plan.update!(
          name: spec[:name],
          description: spec[:description],
          amount_cents: spec[:amount_cents],
          interval: spec[:interval],
          trial_period: spec[:trial_period],
          amount_currency: "USD"
        )
      end
    else
      puts "+ creating plan '#{spec[:code]}'"
      return nil if dry_run
      plan = organization.plans.create!(
        code: spec[:code],
        name: spec[:name],
        description: spec[:description],
        interval: spec[:interval],
        amount_cents: spec[:amount_cents],
        amount_currency: "USD",
        trial_period: spec[:trial_period],
        pay_in_advance: true
      )
    end

    apply_plan_entitlements!(organization, plan, spec[:entitlements], dry_run:)
    plan
  end

  def self.apply_plan_entitlements!(organization, plan, entitlements_spec, dry_run:)
    entitlements_spec.each do |feature_code, privilege_values|
      feature = organization.features.find_by(code: feature_code)
      unless feature
        warn "  ! feature '#{feature_code}' not found; skipping entitlement on plan '#{plan.code}'"
        next
      end

      entitlement = plan.entitlements.find_by(entitlement_feature_id: feature.id)
      if entitlement
        puts "  ✓ plan '#{plan.code}' already entitles feature '#{feature_code}'"
      else
        puts "  + entitling plan '#{plan.code}' with feature '#{feature_code}'"
        next if dry_run
        entitlement = Entitlement::Entitlement.create!(
          organization: organization,
          plan: plan,
          feature: feature
        )
      end

      next if dry_run

      privilege_values.each do |priv_code, value|
        privilege = feature.privileges.find_by(code: priv_code)
        unless privilege
          warn "  ! privilege '#{feature_code}.#{priv_code}' not declared; skipping"
          next
        end
        existing_val = entitlement.values.find_by(entitlement_privilege_id: privilege.id)
        coerced = value.is_a?(Numeric) ? value.to_s : value.to_s
        if existing_val
          if existing_val.value == coerced
            puts "    ✓ '#{feature_code}.#{priv_code}' = #{coerced} (unchanged)"
          else
            puts "    ~ '#{feature_code}.#{priv_code}' = #{existing_val.value} → #{coerced}"
            existing_val.update!(value: coerced)
          end
        else
          puts "    + '#{feature_code}.#{priv_code}' = #{coerced}"
          Entitlement::EntitlementValue.create!(
            organization: organization,
            entitlement: entitlement,
            privilege: privilege,
            value: coerced
          )
        end
      end
    end
  end
end
