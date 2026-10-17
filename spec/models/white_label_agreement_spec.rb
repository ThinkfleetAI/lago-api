# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhiteLabelAgreement do
  let(:agreement) { create(:white_label_agreement) }
  let(:signer) { {name: "Jane", title: "CEO", email: "jane@example.com"} }

  def token_from(url)
    url.split("/white-label/").last
  end

  describe ".from_token" do
    it "finds a pending agreement from its signing link" do
      expect(described_class.from_token(token_from(agreement.signing_url))).to eq(agreement)
    end

    it "returns nil for tampered tokens" do
      expect(described_class.from_token("garbage")).to be_nil
    end

    it "invalidates the signing link once the agreement is accepted" do
      token = token_from(agreement.signing_url)
      agreement.accept!(signer:, request_ip: "1.2.3.4", user_agent: "rspec")

      expect(described_class.from_token(token)).to be_nil
    end

    it "accepts the post-acceptance payment link" do
      agreement.accept!(signer:, request_ip: "1.2.3.4", user_agent: "rspec")

      expect(described_class.from_token(token_from(agreement.payment_resume_url))).to eq(agreement)
    end

    it "invalidates post-acceptance links when the agreement is reset" do
      agreement.accept!(signer:, request_ip: "1.2.3.4", user_agent: "rspec")
      token = token_from(agreement.payment_resume_url)
      agreement.reset_to_pending!(reason: "manual_operator")

      expect(described_class.from_token(token)).to be_nil
      expect(described_class.from_token(token_from(agreement.signing_url))).to eq(agreement)
    end

    context "with a link issued before nonces existed" do
      let(:legacy_token) do
        described_class.verifier.generate(agreement.id, purpose: described_class::TOKEN_PURPOSE, expires_in: 1.day)
      end

      it "is accepted while the agreement is pending" do
        expect(described_class.from_token(legacy_token)).to eq(agreement)
      end

      it "is refused once the agreement has a nonce" do
        agreement.signing_url

        expect(described_class.from_token(legacy_token)).to be_nil
      end

      it "is refused once the agreement is accepted" do
        agreement.update!(status: "accepted")

        expect(described_class.from_token(legacy_token)).to be_nil
      end
    end
  end

  describe "#signing_url" do
    it "is only available while pending" do
      expect(agreement.signing_url).to be_present

      agreement.accept!(signer:, request_ip: "1.2.3.4", user_agent: "rspec")
      expect(agreement.signing_url).to be_nil
    end
  end

  describe "#payment_resume_url" do
    it "is only available once accepted" do
      expect(agreement.payment_resume_url).to be_nil

      agreement.accept!(signer:, request_ip: "1.2.3.4", user_agent: "rspec")
      expect(agreement.payment_resume_url).to be_present
    end
  end
end
