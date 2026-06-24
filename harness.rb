# frozen_string_literal: true

require "sinatra/base"
require "json"
require "uri"
require "active_support/all"

$LOAD_PATH.unshift(File.join(__dir__, "lib"))

LOADED_TARGETS = {}

def load_target(name, path, requires: [])
  begin
    requires.each do |req|
      require_relative req
    end
    require_relative path unless Object.const_defined?(name)
    LOADED_TARGETS[name.to_sym] = true
  rescue LoadError, StandardError => e
    warn "[harness] skipping #{name} from #{path}: #{e.class}: #{e.message}"
    LOADED_TARGETS[name.to_sym] = false
  end
end

# Tier 1 targets
load_target("Search", "lib/search", requires: ["lib/search"])
load_target("UrlHelper", "lib/url_helper", requires: ["lib/url_helper"])
load_target("FileHelper", "lib/file_helper", requires: ["lib/file_helper"])
load_target("PrettyText", "lib/pretty_text", requires: ["lib/pretty_text"])

# Tier 2 targets: minimal DB bootstrap only
begin
  require "active_record"
  ActiveRecord::Base.establish_connection(
    adapter: "postgresql",
    host: ENV["PGHOST"] || ENV["DB_HOST"] || "localhost",
    database: ENV["RAILS_DB"] || ENV["DISCOURSE_DEV_DB"] || "discourse_development",
    username: ENV["DB_USER"] || "postgres"
  )
  load_target("FinalDestination", "lib/final_destination", requires: ["lib/final_destination"])
rescue LoadError, StandardError => e
  warn "[harness] skipping FinalDestination DB bootstrap: #{e.class}: #{e.message}"
  LOADED_TARGETS[:FinalDestination] = false
end

class HarnessApp < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, ENV.fetch("PORT", "3001").to_i

  before do
    content_type "text/plain"
  end

  get "/health" do
    "ok"
  end

  get "/harness/search-prepare-data" do
    halt 404, "Search unavailable" unless LOADED_TARGETS[:Search]
    Search.prepare_data(params["search_data"], params["purpose"])
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/search-unaccent" do
    halt 404, "Search unavailable" unless LOADED_TARGETS[:Search]
    Search.unaccent(params["str"])
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/search-ts-query" do
    halt 404, "Search unavailable" unless LOADED_TARGETS[:Search]
    prefix_match = ActiveModel::Type::Boolean.new.cast(params["prefix_match"])
    Search.ts_query(
      term: params["term"],
      ts_config: params["ts_config"],
      joiner: params["joiner"],
      weight_filter: params["weight_filter"],
      prefix_match: prefix_match
    )
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/search-to-tsquery" do
    halt 404, "Search unavailable" unless LOADED_TARGETS[:Search]
    Search.to_tsquery(
      ts_config: params["ts_config"],
      term: params["term"],
      joiner: params["joiner"]
    )
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/search-escape-string" do
    halt 404, "Search unavailable" unless LOADED_TARGETS[:Search]
    Search.escape_string(params["term"])
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/urlhelper-normalzed-encode" do
    halt 404, "UrlHelper unavailable" unless LOADED_TARGETS[:UrlHelper]
    UrlHelper.normalized_encode(params["uri"])
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/urlhelper-is-valid-url-" do
    halt 404, "UrlHelper unavailable" unless LOADED_TARGETS[:UrlHelper]
    UrlHelper.is_valid_url?(params["url"]).to_s
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/urlhelper-cook-url" do
    halt 404, "UrlHelper unavailable" unless LOADED_TARGETS[:UrlHelper]
    secure = ActiveModel::Type::Boolean.new.cast(params["secure"])
    local = params.key?("local") ? ActiveModel::Type::Boolean.new.cast(params["local"]) : nil
    UrlHelper.cook_url(params["url"], secure: secure, local: local)
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/filehelper-sanitize-filename" do
    halt 404, "FileHelper unavailable" unless LOADED_TARGETS[:FileHelper]
    FileHelper.sanitize_filename(params["filename"])
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/filehelper-is-supported-media-" do
    halt 404, "FileHelper unavailable" unless LOADED_TARGETS[:FileHelper]
    FileHelper.is_supported_media?(params["filename"]).to_s
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/filehelper-download" do
    halt 404, "FileHelper unavailable" unless LOADED_TARGETS[:FileHelper]
    follow_redirect = ActiveModel::Type::Boolean.new.cast(params["follow_redirect"])
    max_file_size = params["max_file_size"].to_i
    tmp_file_name = params["tmp_file_name"].to_s
    tmp = FileHelper.download(
      params["url"],
      max_file_size: max_file_size,
      tmp_file_name: tmp_file_name,
      follow_redirect: follow_redirect
    )
    if tmp
      body tmp.read
      tmp.close!
    else
      ""
    end
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/finaldestination-resolve" do
    halt 404, "FinalDestination unavailable" unless LOADED_TARGETS[:FinalDestination]
    opts = params["opts"] ? JSON.parse(params["opts"]) : {}
    FinalDestination.resolve(params["url"], opts).to_s
  rescue StandardError => e
    halt 500, e.message
  end

  get "/harness/finaldestination-get" do
    halt 404, "FinalDestination unavailable" unless LOADED_TARGETS[:FinalDestination]
    redirects = params["redirects"].to_i
    extra_headers = params["extra_headers"] ? JSON.parse(params["extra_headers"]) : {}
    except_headers = params["except_headers"] ? JSON.parse(params["except_headers"]) : []
    out = +""
    result = FinalDestination.new(params["url"] || "http://127.0.0.1", max_redirects: redirects)
    resolved = result.get(redirects, extra_headers: extra_headers, except_headers: except_headers) do |response, chunk, uri|
      out << chunk.to_s if chunk
    end
    body({ resolved: resolved, output: out }.to_json)
  rescue StandardError => e
    halt 500, e.message
  end

  post "/harness/prettytext-extract-links" do
    halt 404, "PrettyText unavailable" unless LOADED_TARGETS[:PrettyText]
    payload = JSON.parse(request.body.read)
    PrettyText.extract_links(payload["html"]).map(&:to_h).to_json
  rescue StandardError => e
    halt 500, e.message
  end

  post "/harness/prettytext-format-for-email" do
    halt 404, "PrettyText unavailable" unless LOADED_TARGETS[:PrettyText]
    payload = JSON.parse(request.body.read)
    PrettyText.format_for_email(payload["html"], payload["post"]).to_s
  rescue StandardError => e
    halt 500, e.message
  end
end

HarnessApp.run! if __FILE__ == $PROGRAM_NAME
