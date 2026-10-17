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
      # It is not covered by the signed token, so only hosts listed in
      # LAGO_PORTAL_RETURN_TO_HOSTS are kept; anything else is dropped.
      if allowed_return_to?
        url += "?return_to=#{CGI.escape(return_to)}"
      end
      result.url = url

      result
    end

    private

    attr_reader :customer, :return_to

    def allowed_return_to?
      return false if return_to.blank?

      uri = URI.parse(return_to.to_s)
      return false unless %w[http https].include?(uri.scheme&.downcase)
      return false if uri.userinfo.present? || uri.host.blank?

      host = uri.host.downcase
      allowed_return_to_hosts.any? do |allowed|
        if allowed.start_with?("*.")
          host.end_with?(allowed.delete_prefix("*"))
        else
          host == allowed
        end
      end
    rescue URI::InvalidURIError
      false
    end

    def allowed_return_to_hosts
      ENV.fetch("LAGO_PORTAL_RETURN_TO_HOSTS", "").split(",").map { |h| h.strip.downcase }.reject(&:empty?)
    end
  end
end
