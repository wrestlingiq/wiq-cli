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
