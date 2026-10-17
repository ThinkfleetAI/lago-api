# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerPortal::GenerateUrlService do
  subject(:generate_url_service) { described_class.new(customer:) }

  let(:customer) { create(:customer) }

  describe "#call" do
    it "generates valid customer portal url" do
      result = generate_url_service.call

      message = result.url.split("/customer-portal/")[1]
      public_authenticator = ActiveSupport::MessageVerifier.new(ENV["SECRET_KEY_BASE"])

      expect(result.url).to include("/customer-portal/")
      expect(public_authenticator.verify(message)).to eq(customer.id)
    end

    context "with return_to" do
      subject(:generate_url_service) { described_class.new(customer:, return_to:) }

      around do |example|
        previous = ENV["LAGO_PORTAL_RETURN_TO_HOSTS"]
        ENV["LAGO_PORTAL_RETURN_TO_HOSTS"] = "app.example.com, *.tenant.example.com"
        example.run
      ensure
        ENV["LAGO_PORTAL_RETURN_TO_HOSTS"] = previous
      end

      [
        "https://app.example.com/billing",
        "https://acme.tenant.example.com/billing?x=1"
      ].each do |url|
        context "when it targets an allowed host (#{url})" do
          let(:return_to) { url }

          it "appends it to the url" do
            expect(generate_url_service.call.url).to end_with("?return_to=#{CGI.escape(url)}")
          end
        end
      end

      [
        "https://evil.example.net/",
        "https://app.example.com.evil.net/",
        "https://app.example.com@evil.net/",
        "javascript:alert(1)",
        "//evil.example.net",
        "https://tenant.example.com.evil.net/"
      ].each do |url|
        context "when it targets a host that is not allowed (#{url})" do
          let(:return_to) { url }

          it "drops it" do
            expect(generate_url_service.call.url).not_to include("return_to")
          end
        end
      end

      context "when no hosts are configured" do
        let(:return_to) { "https://app.example.com/billing" }

        before { ENV["LAGO_PORTAL_RETURN_TO_HOSTS"] = "" }

        it "drops it" do
          expect(generate_url_service.call.url).not_to include("return_to")
        end
      end
    end

    context "when customer does not exist" do
      let(:customer) { nil }

      it "returns an error" do
        result = generate_url_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end
  end
end
