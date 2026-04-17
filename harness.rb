# frozen_string_literal: true

require "sinatra"
require "json"
require "active_support/all"
require "uri"
require "addressable/uri"
require "pg"

# Minimal bootstrapping for Tier 1/2 targets
require_relative "lib/search"
require_relative "lib/url_helper"
require "final_destination"
require_relative "lib/file_helper"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", "3001").to_i

before do
  content_type "text/plain"
end

get "/health" do
  status 200
  "ok"
end

helpers do
  def parse_bool(value)
    case value
    when true, "true", "1", 1 then true
    else false
    end
  end

  def call_and_render
    begin
      result = yield
      if result.is_a?(String)
        result
      else
        result.inspect
      end
    rescue => e
      status 500
      "#{e.class}: #{e.message}"
    end
  end
end

get "/harness/execute" do
  call_and_render { Search.execute(params["term"]) }
end

get "/harness/word_to_date" do
  call_and_render { Search.word_to_date(params["str"]) }
end

get "/harness/clean_term" do
  call_and_render { Search.clean_term(params["term"]) }
end

get "/harness/ts_query" do
  call_and_render { Search.ts_query(term: params["term"]) }
end

get "/harness/to_tsquery" do
  call_and_render { Search.to_tsquery(term: params["term"]) }
end

get "/harness/normalized_encode" do
  call_and_render { UrlHelper.normalized_encode(params["uri"]) }
end

get "/harness/is_valid_url" do
  call_and_render { UrlHelper.is_valid_url?(params["url"]) }
end

get "/harness/rails_route_from_url" do
  call_and_render { UrlHelper.rails_route_from_url(params["url"]) }
end

get "/harness/resolve" do
  call_and_render { FinalDestination.resolve(params["url"]) }
end

get "/harness/download" do
  call_and_render do
    tmp = FileHelper.download(params["url"])
    tmp ? tmp.read : nil
  end
end

get "/harness/sanitize_filename" do
  call_and_render { FileHelper.sanitize_filename(params["filename"]) }
end

run! if app_file == $0
