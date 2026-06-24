# frozen_string_literal: true

require "sinatra/base"
require "json"
require "uri"
require "addressable/uri"
require "active_support/all"

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
$LOAD_PATH.unshift(File.join(__dir__, "app", "services"))

LOADED_TARGETS = {}

def warn_load(name, err)
  $stderr.puts("[harness] skipping #{name}: #{err.class}: #{err.message}")
end

# Minimal stubs to avoid full framework boot where possible.
unless defined?(Rails)
  module Rails
    def self.root
      Pathname.new(__dir__)
    end

    def self.logger
      @logger ||= Logger.new($stderr)
    end

    def self.configuration
      @configuration ||= OpenStruct.new(developer_emails: [])
    end
  end
end

unless defined?(SiteSetting)
  module SiteSetting
    class << self
      def method_missing(name, *args)
        case name.to_s
        when "default_locale" then "en"
        when "search_ignore_accents" then false
        when "search_tokenize_chinese" then false
        when "search_tokenize_japanese" then false
        when "search_prefer_recent_posts?" then false
        when "search_recent_posts_size" then 0
        when "search_page_size" then 20
        when "hide_user_profiles_from_public" then false
        when "enable_names" then true
        when "enable_listing_suspended_users_on_search" then true
        when "tagging_enabled" then true
        when "search_ranking_weights" then nil
        when "search_ranking_normalization" then 0
        when "prioritize_exact_search_title_match" then false
        when "category_search_priority_low_weight" then 1.0
        when "category_search_priority_high_weight" then 1.0
        when "content_localization_enabled" then false
        when "use_pg_headlines_for_excerpt" then false
        when "log_search_queries?" then false
        when "search_default_sort_order" then 0
        when "min_search_term_length" then 3
        when "secure_uploads" then false
        when "add_rel_nofollow_to_user_content" then false
        when "block_hotlinked_media" then false
        when "block_hotlinked_media_exceptions" then ""
        when "exclude_rel_nofollow_domains" then ""
        when "enable_mentions" then false
        when "enable_emoji?" then false
        when "enable_emoji" then false
        when "enable_emoji_shortcuts" then false
        when "enable_inline_emoji_translation" then false
        when "avatar_sizes" then []
        else
          false
        end
      end

      def respond_to_missing?(*)
        true
      end

      def defaults
        @defaults ||= OpenStruct.new(get: 3)
      end

      def Upload
        OpenStruct.new(enable_s3_uploads: false, s3_cdn_url: nil)
      end
    end
  end
end

unless defined?(Discourse)
  module Discourse
    def self.base_path = ""
    def self.base_url = "http://localhost:3001"
    def self.base_url_no_prefix = "http://localhost:3001"
    def self.asset_host = nil
    def self.store = OpenStruct.new(
      has_been_uploaded?: false,
      external?: false,
      cdn_url: ->(u) { u },
      upload_path: "uploads",
      absolute_base_url: "http://localhost:3001"
    )
    def self.readonly_mode? = false
    def self.cache = OpenStruct.new(fetch: nil)
    def self.route_for(_term) = nil
  end
end

unless defined?(DB)
  module DB
    def self.query(*)
      []
    end
  end
end

unless defined?(PG)
  module PG
    module Connection
      def self.escape_string(str) = str.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'")
    end
  end
end

unless defined?(Guardian)
  class Guardian
    attr_reader :user
    def initialize(user = nil) = (@user = user)
    def can_see_private_messages?(*) = true
    def can_lazy_load_categories? = false
    def can_see?(*) = true
    def can_see_unlisted_topics? = true
    def is_admin? = false
    def secure_category_ids = []
  end
end

unless defined?(User)
  class User
    def self.username_available?(*)
      true
    end

    def self.find_by_username(*) = nil
    def self.normalize_username(s) = s.to_s.downcase
    def self.not_staged = self
    def self.where(*) = self
    def self.pick(*) = nil
  end
end

unless defined?(UserNameSuggester)
  module UserNameSuggester
    def self.suggest(username) = "#{username}123"
  end
end

unless defined?(UsernameValidator)
  class UsernameValidator
    attr_reader :errors
    def initialize(username)
      @username = username
      @errors = []
    end
    def valid_format? = !@username.to_s.empty?
  end
end

unless defined?(Searchable)
  module Searchable
    PRIORITIES = { very_high: 3, very_low: 1, low: 2, high: 4, ignore: 0 }
  end
end

unless defined?(Archetype)
  module Archetype
    def self.default = "regular"
    def self.private_message = "private_message"
  end
end

unless defined?(Topic)
  class Topic
    def self.visible_post_types(*) = [1]
  end
end

unless defined?(Post)
  class Post
    def self.types = { whisper: 1, regular: 0 }
    def self.visible_post_types(*) = [1]
    def self.unscoped = self
    def self.order(*) = self
    def self.offset(*) = self
    def self.limit(*) = self
    def self.pluck(*) = []
  end
end

unless defined?(Category)
  class Category
    def self.where(*) = self
    def self.pluck(*) = []
    def self.normalize_sql(s) = s
    def self.subcategory_ids(*) = []
    def self.includes(*) = self
    def self.references(*) = self
    def self.order(*) = self
    def self.secured(*) = self
    def self.pick(*) = nil
  end
end

unless defined?(Tag)
  class Tag
    def self.where_name(*) = self
    def self.pick(*) = []
    def self.includes(*) = self
    def self.where(*) = self
    def self.where_name(*) = self
  end
end

unless defined?(TagGroup)
  class TagGroup
    def self.find_id_by_slug(*) = nil
  end
end

unless defined?(Group)
  class Group
    def self.visible_groups(*) = self
    def self.members_visible_groups(*) = self
    def self.where(*) = self
    def self.pick(*) = nil
  end
end

unless defined?(DiscoursePluginRegistry)
  module DiscoursePluginRegistry
    def self.search_groups_set_query_callbacks = []
    def self.apply_modifier(*args)
      args[1]
    end
    def self.hashtag_autocomplete_data_sources = []
    def self.hashtag_autocomplete_contextual_type_priorities = []
  end
end

unless defined?(PrettyText)
  begin
    require_relative "lib/pretty_text"
    LOADED_TARGETS[:pretty_text] = true
  rescue => e
    warn_load("PrettyText", e)
  end
end

begin
  require_relative "lib/search"
  LOADED_TARGETS[:search] = true
rescue => e
  warn_load("Search", e)
end

begin
  require_relative "lib/url_helper"
  LOADED_TARGETS[:url_helper] = true
rescue => e
  warn_load("UrlHelper", e)
end

begin
  require_relative "lib/file_helper"
  LOADED_TARGETS[:file_helper] = true
rescue => e
  warn_load("FileHelper", e)
end

begin
  require_relative "app/services/username_checker_service"
  LOADED_TARGETS[:username_checker_service] = true
rescue => e
  warn_load("UsernameCheckerService", e)
end

begin
  require_relative "app/services/hashtag_autocomplete_service"
  LOADED_TARGETS[:hashtag_autocomplete_service] = true
rescue => e
  warn_load("HashtagAutocompleteService", e)
end

begin
  require_relative "lib/onebox"
  LOADED_TARGETS[:onebox] = true
rescue => e
  warn_load("Onebox", e)
end

class HarnessApp < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, (ENV["PORT"] || "3001").to_i

  before do
    content_type "application/json"
  end

  get "/health" do
    JSON.generate(ok: true)
  end

  def parse_bool(v)
    return nil if v.nil?
    %w[1 true yes on].include?(v.to_s.downcase)
  end

  def json_result(value)
    value.is_a?(String) ? value : JSON.generate(value)
  end

  get "/harness/search-execute" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:search]
    begin
      opts = params["opts"] ? JSON.parse(params["opts"]) : {}
      result = Search.execute(params["term"], opts.deep_symbolize_keys)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/search-prepare-data" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:search]
    begin
      purpose = params["purpose"]&.to_sym
      result = Search.prepare_data(params["search_data"], purpose)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/search-ts-query" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:search]
    begin
      result = Search.ts_query(
        term: params["term"],
        ts_config: params["ts_config"],
        weight_filter: params["weight_filter"],
        prefix_match: parse_bool(params["prefix_match"])
      )
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/search-to-tsquery" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:search]
    begin
      result = Search.to_tsquery(term: params["term"], ts_config: params["ts_config"])
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/urlhelper-normalized-encode" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:url_helper]
    begin
      result = UrlHelper.normalized_encode(params["uri"])
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/urlhelper-cook-url" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:url_helper]
    begin
      result = UrlHelper.cook_url(
        params["url"],
        secure: parse_bool(params["secure"]),
        local: params.key?("local") ? parse_bool(params["local"]) : nil
      )
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/prettytext-cook" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:pretty_text]
    begin
      opts = params["opts"] ? JSON.parse(params["opts"]) : {}
      result = PrettyText.cook(params["raw"], opts.deep_symbolize_keys)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/prettytext-format-for-email" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:pretty_text]
    begin
      result = PrettyText.format_for_email(params["html"], nil)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  post "/harness/filehelper-download" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:file_helper]
    begin
      body = request.body.read
      payload = body.empty? ? {} : JSON.parse(body)
      result = FileHelper.download(
        payload["url"],
        max_file_size: payload["max_file_size"],
        tmp_file_name: payload["tmp_file_name"],
        follow_redirect: payload["follow_redirect"],
        read_timeout: payload["read_timeout"]
      )
      json_result(result&.read || result.to_s)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/usernamecheckerservice-check-username" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:username_checker_service]
    begin
      result = UsernameCheckerService.new.check_username(params["username"], params["email"])
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/usernamecheckerservice-check-username-availability" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:username_checker_service]
    begin
      result = UsernameCheckerService.new.check_username_availability(params["username"], params["email"])
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/hashtagautocompleteservice-lookup" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:hashtag_autocomplete_service]
    begin
      slugs = JSON.parse(params["slugs"] || "[]")
      types = JSON.parse(params["types_in_priority_order"] || "[]")
      result = HashtagAutocompleteService.new(Guardian.new).lookup(slugs, types)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/hashtagautocompleteservice-search" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:hashtag_autocomplete_service]
    begin
      types = JSON.parse(params["types_in_priority_order"] || "[]")
      limit = params["limit"] ? params["limit"].to_i : 20
      result = HashtagAutocompleteService.new(Guardian.new).search(params["term"], types, limit: limit)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end

  get "/harness/onebox-preview" do
    halt 404, JSON.generate(error: "target not loaded") unless LOADED_TARGETS[:onebox]
    begin
      options = params["options"] ? JSON.parse(params["options"]) : {}
      result = Onebox.preview(params["url"], options)
      json_result(result)
    rescue => e
      status 500
      JSON.generate(error: e.message)
    end
  end
end

HarnessApp.run!
