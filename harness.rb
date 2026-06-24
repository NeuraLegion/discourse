# frozen_string_literal: true

require "json"
require "uri"
require "sinatra"
require "rack/utils"
require "active_support/all"
require "addressable/uri"

begin
  require "pg"
rescue LoadError
end

begin
  require "mini_mime"
rescue LoadError
end

begin
  require "open-uri"
rescue LoadError
end

# Minimal compatibility shims for standalone execution
module Discourse
  def self.base_path = ""
  def self.base_url = "http://localhost:3001"
  def self.base_url_no_prefix = "http://localhost:3001"
  def self.asset_host = nil
  def self.readonly_mode? = false
  def self.redis
    @redis ||= OpenStruct.new(without_namespace: OpenStruct.new)
  end
end

module GlobalSetting
  def self.method_missing(*) = nil
  def self.respond_to_missing?(*) = true
end

module SiteSetting
  class << self
    def method_missing(name, *args)
      defaults[name]
    end

    def respond_to_missing?(*)
      true
    end

    def defaults
      @defaults ||= OpenStruct.new(get: 1)
    end
  end
end

module Rails
  def self.root = Pathname.new(Dir.pwd)
  def self.logger = Logger.new($stdout)
  def self.application = OpenStruct.new(routes: OpenStruct.new(recognize_path: nil))
end

module RailsMultisite
  module ConnectionManagement
    def self.current_db = "default"
  end
end

module Onebox
  module Helpers
    def self.user_agent = "Harness"
  end

  module DomainChecker
    def self.is_blocked?(_) = false
  end
end

module SSRFDetector
  class DisallowedIpError < StandardError; end
  def self.lookup_and_filter_ips(host) = [host]
end

class Guardian
  def user = nil
  def can_see_private_messages?(_) = false
  def can_lazy_load_categories? = false
  def can_see?(_) = true
  def is_admin? = false
  def can_see_whispers? = false
  def can_see_unlisted_topics? = false
  def secure_category_ids = []
end

# Require only the target files and their minimal dependencies.
require_relative "lib/search"
require_relative "lib/url_helper"
require_relative "lib/git_url"
require_relative "lib/file_helper"
require_relative "lib/final_destination"

# PrettyText and HashtagAutocompleteService are tier-3 / db-backed in the app,
# but they are not included in this harness to avoid full boot.
# If you need to add them later, do so only with minimal targeted stubs/DB setup.

before do
  content_type "text/plain"
end

get "/health" do
  status 200
  "ok"
end

helpers do
  def json_response(obj)
    content_type "application/json"
    obj.to_json
  end

  def param_value(name)
    params[name] || params[name.to_sym]
  end

  def parse_boolean(v)
    return v if v == true || v == false
    return true if v.to_s == "true"
    return false if v.to_s == "false"
    nil
  end

  def parse_object(v)
    return v if v.is_a?(Hash)
    return {} if v.nil? || v == ""
    JSON.parse(v)
  end

  def call_target
    yield
  rescue => e
    status 500
    e.message
  end
end

get "/harness/clean_term" do
  call_target { Search.clean_term(param_value("term")) }
end

get "/harness/prepare_data" do
  call_target do
    Search.prepare_data(param_value("search_data"), param_value("purpose")&.to_sym)
  end
end

get "/harness/word_to_date" do
  call_target do
    result = Search.word_to_date(param_value("str"))
    result.nil? ? "" : result.to_s
  end
end

get "/harness/is_valid_url" do
  call_target { UrlHelper.is_valid_url?(param_value("url")) }
end

get "/harness/normalized_encode" do
  call_target { UrlHelper.normalized_encode(param_value("uri")) }
end

get "/harness/git_normalize" do
  call_target { GitUrl.normalize(param_value("url")) }
end

post "/harness/sanitize_filename" do
  call_target { FileHelper.sanitize_filename(param_value("filename")) }
end

get "/harness/is_supported_media" do
  call_target { FileHelper.is_supported_media?(param_value("filename")) }
end

get "/harness/cook_url" do
  call_target do
    url = param_value("url")
    secure = parse_boolean(param_value("secure"))
    local = parse_boolean(param_value("local"))
    if local.nil?
      UrlHelper.cook_url(url, secure: secure || false)
    else
      UrlHelper.cook_url(url, secure: secure || false, local: local)
    end
  end
end

get "/harness/relaxed_parse" do
  call_target do
    result = UrlHelper.relaxed_parse(param_value("url"))
    result.nil? ? "" : result.to_s
  end
end

get "/harness/final_destination_resolve" do
  call_target do
    opts = parse_object(param_value("opts"))
    result = FinalDestination.resolve(param_value("url"), opts)
    result.nil? ? "" : result.to_s
  end
end

get "/harness/final_destination_get" do
  call_target do
    redirects = param_value("redirects").to_i
    fd = FinalDestination.new("https://example.com", max_redirects: redirects)
    result = fd.get(redirects) { |_resp, _chunk, _uri| }
    result.nil? ? "" : result.to_s
  end
end

set :bind, "0.0.0.0"
set :port, (ENV["PORT"] || "3001").to_i
start!
