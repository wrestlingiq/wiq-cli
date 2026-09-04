# frozen_string_literal: true

RSpec.describe Wiq::APIError do
  def build(status, body)
    described_class.new(status: status, body: body)
  end

  it "maps 401 to unauthorized and points the user at auth login" do
    err = build(401, { "errors" => ["Unauthorized"] })
    expect(err.code).to eq("unauthorized")
    expect(err.hint).to include("wiq auth")
  end

  it "maps 403 to forbidden and surfaces the server's message" do
    err = build(403, { "errors" => ["Not Authorized To View Content"] })
    expect(err.code).to eq("forbidden")
    expect(err.message).to include("Not Authorized To View Content")
  end

  context "403 — the three PAT write denials from enforce_pat_restrictions" do
    it "keys 'not writable with a personal access token' to pat_write_unsupported" do
      err = build(403, { "errors" => ["This endpoint is not writable with a personal access token."] })
      expect(err.code).to eq("pat_write_unsupported")
      expect(err.capability).to be_nil
      expect(err.hint).to include("web app")
    end

    it "treats the pre-scopes 'read-only' wording the same way" do
      err = build(403, { "errors" => ["Personal access tokens are read-only in this release except for report creation."] })
      expect(err.code).to eq("pat_write_unsupported")
    end

    it "keys 'team has not enabled <cap>' to capability_disabled_for_team and extracts the capability" do
      err = build(403, { "errors" => ["This team has not enabled prospects:write for API access. A team admin can enable it in team settings."] })
      expect(err.code).to eq("capability_disabled_for_team")
      expect(err.capability).to eq("prospects:write")
      expect(err.hint).to include("settings/team/api_access")
      expect(err.hint).to include("prospects:write")
    end

    it "keys 'token lacks the <cap> scope' to token_missing_scope and points at minting a new token" do
      err = build(403, { "errors" => ["This token lacks the prospects:write scope. Revoke it and mint a new token that includes prospects:write."] })
      expect(err.code).to eq("token_missing_scope")
      expect(err.capability).to eq("prospects:write")
      expect(err.hint).to include("wiq auth login --force")
      expect(err.hint).to include("settings/personal_access_tokens")
    end

    it "leaves a plain Pundit denial as forbidden" do
      err = build(403, { "errors" => ["Not Authorized To View Content"] })
      expect(err.code).to eq("forbidden")
      expect(err.capability).to be_nil
    end
  end

  it "keys the PAT forward-only stage refusal (422) to stage_transition_refused" do
    err = build(422, { "errors" => ["Stage cannot move from converted to trialing with a personal access token — stage changes are forward-only via the API and cannot leave a terminal stage. A coach can make this change in the web app."] })
    expect(err.code).to eq("stage_transition_refused")
    expect(err.hint).to include("forward-only")
  end

  it "maps 404 to not_found" do
    err = build(404, { "errors" => ["Not Found"] })
    expect(err.code).to eq("not_found")
  end

  it "maps 429 to rate_limited with a backoff hint" do
    err = build(429, { "errors" => ["Slow down"] })
    expect(err.code).to eq("rate_limited")
    expect(err.hint).to match(/100 req\/3s/)
  end

  context "422 — the two response shapes documented in wiq_api_notes.md" do
    it "flattens an array of strings (rare path: explicit validation_error([...]))" do
      err = build(422, { "errors" => ["Name can't be blank", "Email is invalid"] })
      expect(err.code).to eq("validation_failed")
      expect(err.message).to include("Name can't be blank")
      expect(err.message).to include("Email is invalid")
    end

    it "flattens an ActiveModel::Errors hash (common path: validation_error(@model.errors))" do
      err = build(422, { "errors" => { "name" => ["can't be blank"], "email" => ["is invalid", "is too short"] } })
      expect(err.code).to eq("validation_failed")
      expect(err.message).to include("name: can't be blank")
      expect(err.message).to include("email: is invalid")
      expect(err.message).to include("email: is too short")
    end
  end

  it "falls through to http_<status> for unknown status codes" do
    err = build(418, { "errors" => ["I'm a teapot"] })
    expect(err.code).to eq("http_418")
  end

  it "tolerates a missing errors key without crashing" do
    err = build(500, {})
    expect(err.code).to eq("http_500")
    expect(err.message).to include("no error body").or include("HTTP 500")
  end
end
