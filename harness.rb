# frozen_string_literal: true

require "json"
require "sinatra/base"
require "uri"
require "addressable/uri"
require "tempfile"
require "set"

$LOAD_PATH.unshift(File.join(__dir__, "lib"))

begin
  require "active_support/all"
rescue LoadError => e
  warn "WARN: active_support/all not available: #{e.message}"
end

begin
  require "active_record"
rescue LoadError => e
  warn "WARN: active_record not available: #{e.message}"
end

begin
  require "pg"
rescue LoadError => e
  warn "WARN: pg not available: #{e.message}"
end

# Minimal framework stubs needed by the target files.

unless defined?(Rails)
  module Rails
    def self.logger
      @logger ||= Class.new do
        def method_missing(*); end
        def respond_to_missing?(*); true; end
      end.new
    end
  end
end

unless defined?(RailsMultisite)
  module RailsMultisite
    module ConnectionManagement
      def self.current_db
        ENV["PGDATABASE"] || "default"
      end
    end
  end
end

unless defined?(Discourse)
  module Discourse
    class InvalidParameters < StandardError; end
  end
end

unless defined?(SiteSetting)
  module SiteSetting
    class << self
      def permalink_normalizations
        ""
      end

      def max_tag_search_results
        20
      end

      def max_tag_length
        100
      end

      def force_lowercase_tags
        true
      end
    end
  end
end

if defined?(ActiveRecord::Base)
  begin
    ActiveRecord::Base.establish_connection(
      adapter: "postgresql",
      host: ENV["PGHOST"],
      port: ENV["PGPORT"],
      database: ENV["PGDATABASE"],
      username: ENV["PGUSER"],
      password: ENV["PGPASSWORD"]
    )
  rescue => e
    warn "WARN: ActiveRecord connection failed: #{e.class}: #{e.message}"
  end
end

class HarnessServer < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, ENV.fetch("PORT", "3001").to_i
  set :logging, false

  LOADED_TARGETS = {}

  helpers do
    def json_body
      request.body.rewind
      body = request.body.read
      body.to_s.empty? ? {} : JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def stringify_result(result)
      return "" if result.nil?
      return result.to_json if result.is_a?(Hash) || result.is_a?(Array)
      return result.read if result.respond_to?(:read)
      result.to_s
    end

    def safe_call
      yield
    rescue => e
      status 500
      "ERROR: #{e.class}: #{e.message}"
    end
  end

  get "/health" do
    status 200
    "ok"
  end

  begin
    require_relative "lib/final_destination"
    require_relative "lib/file_helper"
    LOADED_TARGETS[:filehelper_download] = true
    warn "Loaded FileHelper.download"
  rescue => e
    LOADED_TARGETS[:filehelper_download] = false
    warn "WARN: skipping FileHelper.download: #{e.class}: #{e.message}"
  end

  begin
    require_relative "lib/url_helper"
    LOADED_TARGETS[:urlhelper_normalize_and_parse] = true
    warn "Loaded UrlHelper.normalize_and_parse"
  rescue => e
    LOADED_TARGETS[:urlhelper_normalize_and_parse] = false
    warn "WARN: skipping UrlHelper.normalize_and_parse: #{e.class}: #{e.message}"
  end

  begin
    require_relative "app/models/permalink"
    LOADED_TARGETS[:permalink_normalize_url] = true
    LOADED_TARGETS[:permalink_find_by_url] = true
    warn "Loaded Permalink targets"
  rescue => e
    LOADED_TARGETS[:permalink_normalize_url] = false
    LOADED_TARGETS[:permalink_find_by_url] = false
    warn "WARN: skipping Permalink targets: #{e.class}: #{e.message}"
  end

  begin
    require_relative "lib/service"
    require_relative "lib/discourse_tagging"
    require_relative "app/services/tags/search"
    LOADED_TARGETS[:tags_search] = true
    warn "Loaded Tags::Search.search"
  rescue => e
    LOADED_TARGETS[:tags_search] = false
    warn "WARN: skipping Tags::Search.search: #{e.class}: #{e.message}"
  end

  begin
    require_relative "lib/service"
    require_relative "lib/discourse_tagging"
    require_relative "app/services/tags/bulk_create"
    require_relative "app/models/tag"
    LOADED_TARGETS[:tags_bulk_create] = true
    warn "Loaded Tags::BulkCreate.call"
  rescue => e
    LOADED_TARGETS[:tags_bulk_create] = false
    warn "WARN: skipping Tags::BulkCreate.call: #{e.class}: #{e.message}"
  end

  get "/harness/filehelper-download" do
    halt 404, "not loaded" unless LOADED_TARGETS[:filehelper_download]
    safe_call do
      result = FileHelper.download(
        params["url"],
        max_file_size: params["max_file_size"].to_i,
        tmp_file_name: params["tmp_file_name"]
      )
      stringify_result(result)
    end
  end

  get "/harness/urlhelper-normalize-and-parse" do
    halt 404, "not loaded" unless LOADED_TARGETS[:urlhelper_normalize_and_parse]
    safe_call do
      url = params["url"]
      result =
        if UrlHelper.respond_to?(:normalize_and_parse)
          UrlHelper.normalize_and_parse(url)
        else
          normalized = UrlHelper.normalized_encode(url)
          URI.parse(normalized)
        end
      stringify_result(result)
    end
  end

  get "/harness/permalink-normalize-url" do
    halt 404, "not loaded" unless LOADED_TARGETS[:permalink_normalize_url]
    safe_call do
      result = Permalink.normalize_url(params["url"])
      stringify_result(result)
    end
  end

  get "/harness/permalink-find-by-url" do
    halt 404, "not loaded" unless LOADED_TARGETS[:permalink_find_by_url]
    safe_call do
      result = Permalink.find_by_url(params["url"])
      stringify_result(result)
    end
  end

  get "/harness/tags--search-search" do
    halt 404, "not loaded" unless LOADED_TARGETS[:tags_search]
    safe_call do
      params_hash = params["params"]
      params_hash = JSON.parse(params_hash) if params_hash.is_a?(String) && params_hash.start_with?("{")
      params_hash ||= {}

      if Tags::Search.respond_to?(:search)
        result = Tags::Search.search(Object.new, params_hash)
      else
        result = Tags::Search.call(guardian: Object.new, params: params_hash)
      end

      stringify_result(result)
    end
  end

  post "/harness/tags--bulkcreate-call" do
    halt 404, "not loaded" unless LOADED_TARGETS[:tags_bulk_create]
    safe_call do
      body = json_body
      params_hash = body["params"] || {}

      if Tags::BulkCreate.respond_to?(:call)
        result = Tags::BulkCreate.call(guardian: Object.new, params: params_hash)
      else
        result = Tags::BulkCreate.call(Object.new, params_hash)
      end

      stringify_result(result)
    end
  end
end

HarnessServer.run!
