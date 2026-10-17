# frozen_string_literal: true

# The test suite has no DNS access and factories use random hostnames.
# Resolve every hostname to a fixed public address by default. This is done
# at load time rather than only in a `before` hook so that records created in
# `around` hooks or `before(:all)` blocks are covered as well.
LagoHttpClient::OutboundUrlGuard.singleton_class.class_eval do
  def resolve_host(_host)
    ["93.184.215.14"]
  end
end

# Spy on the resolver so specs can assert whether it was called; specs
# exercising the guard override `resolve_host` explicitly.
RSpec.configure do |config|
  config.before do
    allow(LagoHttpClient::OutboundUrlGuard).to receive(:resolve_host).and_call_original
  end
end
