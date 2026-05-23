# frozen_string_literal: true

module CustomerPortal
  class GenerateUrlService < BaseService
    def initialize(customer:, return_to: nil)
      @customer = customer
      @return_to = return_to

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") if customer.blank?

      public_authenticator = ActiveSupport::MessageVerifier.new(ENV["SECRET_KEY_BASE"])
      message = public_authenticator.generate(customer.id, expires_in: 12.hours)

      url = "#{ENV["LAGO_FRONT_URL"]}/customer-portal/#{message}"
      # return_to lets the host app self-heal a stale portal tab: when the
      # JWT expires, lago-front bounces back to this URL with ?refresh=1 so
      # the host app's billing page can mint a fresh URL.
      if return_to.present?
        url += "?return_to=#{CGI.escape(return_to)}"
      end
      result.url = url

      result
    end

    private

    attr_reader :customer, :return_to
  end
end
