# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoHttpClient::OutboundUrlGuard do
  describe ".resolve!" do
    context "when the host resolves to a public address" do
      before { allow(described_class).to receive(:resolve_host).with("hooks.example.com").and_return(["93.184.215.14"]) }

      it "returns the address to pin the connection to" do
        expect(described_class.resolve!("https://hooks.example.com/path")).to eq("93.184.215.14")
      end
    end

    [
      "127.0.0.1", "127.1.2.3", "0.0.0.0", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1",
      "169.254.169.254", "100.64.0.1", "100.100.100.200", "192.0.0.192", "198.18.0.1", "224.0.0.1",
      "255.255.255.255", "::1", "::", "fe80::1", "fc00::1", "fd00:ec2::254", "ff02::1",
      "::ffff:127.0.0.1", "::ffff:169.254.169.254", "::ffff:a9fe:a9fe", "64:ff9b::a9fe:a9fe", "2002:7f00:1::1"
    ].each do |address|
      it "rejects #{address} when it is the resolved address" do
        allow(described_class).to receive(:resolve_host).and_return([address])

        expect { described_class.resolve!("https://internal.example.com/") }
          .to raise_error(described_class::DisallowedDestinationError)
      end
    end

    it "rejects IP literals in non-public ranges without resolving" do
      expect { described_class.resolve!("http://127.0.0.1:3000/") }.to raise_error(described_class::DisallowedDestinationError)
      expect { described_class.resolve!("http://[::1]/") }.to raise_error(described_class::DisallowedDestinationError)
      expect { described_class.resolve!("http://[::ffff:10.0.0.1]/") }.to raise_error(described_class::DisallowedDestinationError)
      expect(described_class).not_to have_received(:resolve_host)
    end

    it "accepts public IP literals" do
      expect(described_class.resolve!("https://8.8.8.8/")).to eq("8.8.8.8")
      expect(described_class.resolve!("https://[2606:4700:4700::1111]/")).to eq("2606:4700:4700::1111")
    end

    it "rejects the host when any resolved address is not public" do
      allow(described_class).to receive(:resolve_host).and_return(["93.184.215.14", "10.0.0.5"])

      expect { described_class.resolve!("https://mixed.example.com/") }.to raise_error(described_class::DisallowedDestinationError)
    end

    it "rejects hosts that do not resolve" do
      allow(described_class).to receive(:resolve_host).and_return([])

      expect { described_class.resolve!("https://nowhere.example.com/") }.to raise_error(described_class::DisallowedDestinationError)
    end

    it "rejects non-HTTP schemes and malformed URLs" do
      ["ftp://example.com/", "file:///etc/hosts", "gopher://example.com", "not a url", "http://"].each do |url|
        expect { described_class.resolve!(url) }.to raise_error(described_class::DisallowedDestinationError)
      end
    end

    context "when LAGO_OUTBOUND_ALLOW_PRIVATE is enabled" do
      around do |example|
        previous = ENV["LAGO_OUTBOUND_ALLOW_PRIVATE"]
        ENV["LAGO_OUTBOUND_ALLOW_PRIVATE"] = "true"
        example.run
      ensure
        ENV["LAGO_OUTBOUND_ALLOW_PRIVATE"] = previous
      end

      it "allows private destinations outside production" do
        expect(described_class.resolve!("http://127.0.0.1:3000/")).to be_nil
      end

      it "is ignored in production" do
        allow(Rails.env).to receive(:production?).and_return(true)

        expect { described_class.resolve!("http://127.0.0.1:3000/") }.to raise_error(described_class::DisallowedDestinationError)
      end
    end
  end

  describe ".allowed?" do
    it "returns a boolean" do
      expect(described_class.allowed?("https://hooks.example.com/")).to be(true)
      expect(described_class.allowed?("http://169.254.169.254/latest/meta-data/")).to be(false)
    end
  end

  describe ".valid_hostname?" do
    it "accepts plain hostnames only" do
      expect(described_class.valid_hostname?("acme.okta.com")).to be(true)
      expect(described_class.valid_hostname?("acme.okta.com/path")).to be(false)
      expect(described_class.valid_hostname?("user@acme.okta.com")).to be(false)
      expect(described_class.valid_hostname?("acme.okta.com:8080")).to be(false)
      expect(described_class.valid_hostname?(nil)).to be(false)
    end
  end
end
