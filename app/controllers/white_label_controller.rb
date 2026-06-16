# frozen_string_literal: true

# Public, login-less MSA acceptance gate for white-label / SDK customers.
#
# Inherits ActionController::Base (not the API base) so it can serve a single
# self-contained HTML page. Authentication is the signed token in the URL, so
# CSRF/forgery protection is disabled — the token is the bearer credential.
#
#   GET  /white-label/:token          -> render MSA + Terms + acceptance form
#   POST /white-label/:token/accept   -> record signature, redirect to Stripe
#
# After the signer saves a card on Stripe, the `setup_intent.succeeded` webhook
# calls WhiteLabel::ActivateService, which creates the subscription. So this
# controller never touches billing directly — it only captures consent + a card.
#
# ApplicationController is ActionController::API (no HTML rendering) and every
# interpolated value is escaped via ERB::Util.html_escape, so the two Rails cops
# below are intentionally disabled for this trusted-markup controller.
# rubocop:disable Rails/ApplicationController, Rails/OutputSafety
class WhiteLabelController < ActionController::Base
  skip_forgery_protection

  def show
    agreement = WhiteLabelAgreement.from_token(params[:token])
    return render_invalid if agreement.nil?
    return render_status(agreement) unless agreement.status == "pending"

    render_gate(agreement)
  end

  def accept
    agreement = WhiteLabelAgreement.from_token(params[:token])
    return render_invalid if agreement.nil?
    return render_status(agreement) unless agreement.status == "pending"

    unless params[:accept] == "1" && params[:signer_name].present? && params[:signer_title].present?
      return render_gate(agreement, error: "Please enter your name and title and check the acceptance box.")
    end

    agreement.accept!(
      signer: {name: params[:signer_name], title: params[:signer_title], email: params[:signer_email]},
      request_ip: request.remote_ip,
      user_agent: request.user_agent
    )

    checkout = ::Customers::GenerateCheckoutUrlService.call(customer: agreement.customer)
    if checkout.success? && checkout.checkout_url.present?
      redirect_to checkout.checkout_url, allow_other_host: true
    else
      # Card setup not available yet (e.g. Stripe customer still provisioning).
      # Consent is recorded; payment instructions will follow by email.
      render_accepted_without_card
    end
  end

  private

  def render_gate(agreement, error: nil)
    msa = doc_body("msa", agreement.msa_version)
    terms = doc_body("terms", agreement.terms_version)
    company = agreement.customer.name
    err_html = error ? %(<p class="err">#{ERB::Util.html_escape(error)}</p>) : ""

    body = <<~HTML
      <h1>White-Label / SDK Agreement</h1>
      <p class="lead">Please review and accept the agreement below on behalf of
        <strong>#{ERB::Util.html_escape(company)}</strong>. After accepting, you'll
        be taken to a secure page to add a payment method — no account or login required.</p>
      #{err_html}
      <h2>Master Services & White-Label / SDK License Agreement (#{agreement.msa_version})</h2>
      <pre class="doc">#{ERB::Util.html_escape(msa)}</pre>
      <h2>Acceptable Use & Service Terms (#{agreement.terms_version})</h2>
      <pre class="doc">#{ERB::Util.html_escape(terms)}</pre>
      <form method="post" action="/white-label/#{ERB::Util.html_escape(params[:token])}/accept">
        <label>Full name<input name="signer_name" required value="#{ERB::Util.html_escape(params[:signer_name].to_s)}"></label>
        <label>Title<input name="signer_title" required value="#{ERB::Util.html_escape(params[:signer_title].to_s)}"></label>
        <label>Email<input name="signer_email" type="email" value="#{ERB::Util.html_escape(agreement.customer.email.to_s)}"></label>
        <label class="check"><input type="checkbox" name="accept" value="1" required>
          I am authorized to bind #{ERB::Util.html_escape(company)} and I accept the agreement and terms above.</label>
        <button type="submit">Accept &amp; Continue to Payment</button>
      </form>
    HTML
    render html: layout(body).html_safe
  end

  def render_status(agreement)
    msg = case agreement.status
    when "accepted" then "This agreement has already been accepted. If you still need to add a payment method, please use the link in your email or contact us."
    when "active" then "This agreement is active and billing is set up. Nothing further is needed."
    else "This agreement is no longer available."
    end
    render html: layout("<h1>White-Label / SDK Agreement</h1><p class=\"lead\">#{msg}</p>").html_safe
  end

  def render_accepted_without_card
    body = '<h1>Thank you</h1><p class="lead">Your acceptance has been recorded. ' \
      "We will email you a secure link to add your payment method shortly.</p>"
    render html: layout(body).html_safe
  end

  def render_invalid
    render html: layout('<h1>Link expired or invalid</h1><p class="lead">This acceptance ' \
      "link is no longer valid. Please contact your Flobyte representative for a new link.</p>").html_safe,
      status: :not_found
  end
  # rubocop:enable Rails/ApplicationController, Rails/OutputSafety

  # Read a versioned legal doc, stripping the leading HTML comment header.
  def doc_body(kind, version)
    path = Rails.root.join("config/white_label/#{kind}_#{version}.md")
    raw = File.exist?(path) ? File.read(path) : "Document unavailable."
    raw.sub(/\A<!--.*?-->\s*/m, "").strip
  end

  def layout(inner)
    <<~HTML
      <!doctype html><html lang="en"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>White-Label / SDK Agreement</title>
      <style>
        body{font:16px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1a1a1a;
          max-width:760px;margin:0 auto;padding:32px 20px;background:#fafafa}
        h1{font-size:26px;margin:0 0 8px} h2{font-size:18px;margin:28px 0 8px}
        .lead{color:#444} .err{background:#fde8e8;color:#9b1c1c;padding:10px 14px;border-radius:8px}
        pre.doc{white-space:pre-wrap;background:#fff;border:1px solid #e2e2e2;border-radius:10px;
          padding:18px;max-height:320px;overflow:auto;font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
        form{background:#fff;border:1px solid #e2e2e2;border-radius:10px;padding:18px;margin-top:24px}
        label{display:block;margin:0 0 14px;font-weight:600}
        label.check{font-weight:400;display:flex;gap:8px;align-items:flex-start}
        input[type=text],input[name=signer_name],input[name=signer_title],input[type=email]{
          display:block;width:100%;margin-top:6px;padding:10px;border:1px solid #ccc;border-radius:8px;font-size:15px;font-weight:400}
        button{background:#111;color:#fff;border:0;border-radius:8px;padding:12px 18px;font-size:15px;cursor:pointer}
      </style></head><body>#{inner}</body></html>
    HTML
  end
end
