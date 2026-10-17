# frozen_string_literal: true

FactoryBot.define do
  factory :white_label_agreement do
    customer
    organization { customer.organization }
    plan_code { "white-label" }
    msa_version { "v1" }
    terms_version { "v1" }
    status { "pending" }
  end
end
