# frozen_string_literal: true

require "ipaddr"
require "socket"
require "uri"

module LagoHttpClient
  # Restricts outbound HTTP calls made to customer-supplied URLs (webhook
  # endpoints, integration hosts, ...) to public internet destinations.
  #
  # The host is resolved once, every resolved address is checked against
  # non-public ranges, and the caller is expected to pin the connection to
  # the returned address so the checked address is the one actually used.
  #
  # Set LAGO_OUTBOUND_ALLOW_PRIVATE=true to disable the checks in local
  # development. The flag is ignored when Rails runs in production.
  class OutboundUrlGuard
    class DisallowedDestinationError < SocketError; end

    ALLOWED_SCHEMES = %w[http https].freeze

    BLOCKED_IPV4_RANGES = %w[
      0.0.0.0/8
      10.0.0.0/8
      100.64.0.0/10
      127.0.0.0/8
      169.254.0.0/16
      172.16.0.0/12
      192.0.0.0/24
      192.0.2.0/24
      192.88.99.0/24
      192.168.0.0/16
      198.18.0.0/15
      198.51.100.0/24
      203.0.113.0/24
      224.0.0.0/4
      240.0.0.0/4
      255.255.255.255/32
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    BLOCKED_IPV6_RANGES = %w[
      ::/96
      ::ffff:0:0/96
      64:ff9b:1::/48
      100::/64
      2001::/23
      2001:db8::/32
      fc00::/7
      fe80::/10
      fec0::/10
      ff00::/8
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    # IPv6 prefixes that embed an IPv4 address which must itself be public.
    NAT64_PREFIX = IPAddr.new("64:ff9b::/96")
    SIX_TO_FOUR_PREFIX = IPAddr.new("2002::/16")
    IPV4_MAPPED_PREFIX = IPAddr.new("::ffff:0:0/96")

    HOSTNAME_REGEX = /\A(?=.{1,253}\z)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\z/i

    class << self
      # Validates the URL and returns the IP address (String) the connection
      # must be pinned to, or nil when checks are disabled.
      # Raises DisallowedDestinationError otherwise.
      def resolve!(url)
        uri = url.is_a?(URI::Generic) ? url : URI.parse(url.to_s)

        unless ALLOWED_SCHEMES.include?(uri.scheme&.downcase) && uri.hostname.present?
          raise DisallowedDestinationError, "outbound destination is not allowed"
        end

        return nil if allow_private?

        host = uri.hostname
        addresses = ip_literal?(host) ? [host] : resolve_host(host)

        if addresses.blank?
          raise DisallowedDestinationError, "outbound destination could not be resolved"
        end

        ips = addresses.map { |address| IPAddr.new(address) }
        if ips.any? { |ip| blocked_ip?(ip) }
          raise DisallowedDestinationError, "outbound destination is not allowed"
        end

        ips.first.to_s
      rescue URI::InvalidURIError, IPAddr::InvalidAddressError
        raise DisallowedDestinationError, "outbound destination is not allowed"
      end

      # Boolean helper for model validations.
      def allowed?(url)
        resolve!(url)
        true
      rescue DisallowedDestinationError
        false
      end

      def valid_hostname?(host)
        host.is_a?(String) && HOSTNAME_REGEX.match?(host)
      end

      def blocked_ip?(ip)
        ip = IPAddr.new(ip.to_s) unless ip.is_a?(IPAddr)

        if ip.ipv4?
          return BLOCKED_IPV4_RANGES.any? { |range| range.include?(ip) }
        end

        embedded = embedded_ipv4(ip)
        return blocked_ip?(embedded) if embedded

        BLOCKED_IPV6_RANGES.any? { |range| range.include?(ip) }
      end

      def allow_private?
        return false if ENV["LAGO_OUTBOUND_ALLOW_PRIVATE"].to_s.downcase != "true"
        return false if defined?(Rails) && Rails.env.production?

        true
      end

      def resolve_host(host)
        Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
      rescue SocketError
        []
      end

      private

      def ip_literal?(host)
        IPAddr.new(host)
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      def embedded_ipv4(ip)
        if IPV4_MAPPED_PREFIX.include?(ip)
          ip.native
        elsif NAT64_PREFIX.include?(ip)
          IPAddr.new(ip.to_i & 0xffff_ffff, Socket::AF_INET)
        elsif SIX_TO_FOUR_PREFIX.include?(ip)
          IPAddr.new((ip.to_i >> 80) & 0xffff_ffff, Socket::AF_INET)
        end
      end
    end
  end
end
