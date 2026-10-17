# frozen_string_literal: true

# The test suite has no DNS access and factories use random hostnames.
# Resolve every hostname to a fixed public address by default;
# specs exercising the guard override `resolve_host` explicitly.
RSpec.configure do |config|
  config.before do
    allow(LagoHttpClient::OutboundUrlGuard).to receive(:resolve_host).and_return(["93.184.215.14"])
  end
end
