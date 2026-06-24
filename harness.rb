# frozen_string_literal: true

require "sinatra"
require "json"

$LOAD_PATH.unshift(File.join(__dir__, "lib"))

require "active_support/all"

# -----------------------------------------------------------------------------
# Minimal bootstrap / stubs
# -----------------------------------------------------------------------------

class HarnessRedis
  def without_namespace = self
  def get(*) = nil
  def setex(*) = nil
  def del(*) = nil
end

class HarnessCache
  def fetch(*)
    yield
  end
end

class HarnessStore
  def external? = false
  def has_been_uploaded?(*) = false
  def cdn_url(url) = url
  def absolute_base_url = "http://localhost"
  def upload_path = "uploads"
end

module Discourse
  def self.readonly_mode? = false
  def self.cache = (@cache ||= HarnessCache.new)
  def self.redis = (@redis ||= HarnessRedis.new)
  def self.store = (@store ||= HarnessStore.new)
  def self.base_url = "http://localhost"
  def self.base_url_no_prefix = "http://localhost"
  def self.base_path = ""
  def self.asset_host = nil
  def self.route_for(*) = nil
end

module GlobalSetting
  def self.mini_racer_single_threaded = false
  def self.s3_cdn_url = nil
  def self.cdn_url = nil
end

module SiteSetting
  class << self
    def default_locale = "en"
    def search_page_size = 10
    def min_search_term_length = 1
    def search_ignore_accents = false
    def search_tokenize_chinese = false
    def search_tokenize_japanese = false
    def tagging_enabled = false
    def search_prefer_recent_posts? = false
    def search_default_sort_order = :relevance
    def hide_user_profiles_from_public = false
    def enable_names = false
    def enable_listing_suspended_users_on_search = false
    def prioritize_exact_search_title_match = false
    def search_ranking_weights = nil
    def search_ranking_normalization = 0
    def use_pg_headlines_for_excerpt = false
    def log_search_queries? = false
    def content_localization_enabled = false
    def add_rel_nofollow_to_user_content = false
    def search_recent_regular_posts_offset_post_id = 0
    def block_hotlinked_media = false
    def block_hotlinked_media_exceptions = ""
    def secure_uploads = false
    def external_emoji_url = nil
    def enable_emoji? = false
    def enable_emoji = false
    def enable_emoji_shortcuts = false
    def enable_inline_emoji_translation = false
    def avatar_sizes = []
    def client_settings_json = "{}"
    def markdown_additional_options = {}
    def defaults = self
    def get(*)
      1
    end

    def method_missing(name, *args)
      return false if name.to_s.end_with?("?")
      nil
    end
  end
end

module RailsMultisite
  module ConnectionManagement
    def self.current_db = "default"
  end
end

module I18n
  def self.t(key, **opts)
    "#{key}#{opts.empty? ? "" : " #{opts.to_json}"}"
  end
end

module DiscourseEvent
  def self.trigger(*); end
end

module DiscoursePluginRegistry
  def self.search_groups_set_query_callbacks = []
  def self.apply_modifier(*args) = args[1]
  def self.vendored_core_pretty_text = []
  def self.vendored_pretty_text = []
end

module Emoji
  def self.custom = []
  def self.unicode_replacements_json = "{}"
  def self.denied = []
end

module WordWatcher
  def self.serialized_regexps_for_action(*) = []
  def self.regexps_for_action(*) = []
end

module HashtagAutocompleteService
  def self.ordered_types_for_context(*) = []
  def self.data_source_icon_map = {}
end

module Plugin
  module CustomEmoji
    def self.translations = {}
  end
end

module Upload
  def self.secure_uploads_url?(*) = false
  def self.secure_uploads_url_from_upload_url(url) = url
  def self.base62_sha1(str) = str
end

class Guardian
  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def can_see_private_messages?(*) = true
  def can_lazy_load_categories? = false
  def can_see?(*) = true
  def can_see_whispers? = true
  def is_admin? = true
  def can_see_unlisted_topics? = true
  def secure_category_ids = []
end

class SearchLog
  def self.log(**) = [:ok, 1]
end

class GroupedSearchResults
  attr_accessor :search_log_id

  def initialize(**)
    @items = []
  end

  def add(item)
    @items << item
  end

  def type_filter = nil
  def posts = []
end

class SearchSortOrderSiteSetting
  def self.value_from_id(*) = :relevance
  def self.id_from_value(*) = :relevance
end

class Searchable
  PRIORITIES = { ignore: 0, very_high: 3, very_low: 1, low: 2, high: 4 }
end

class Topic; end
class Post
  def self.unscoped = all
end
class Category; end
class Badge; end
class User; end
class Tag; end
class TagGroup; end
class Group; end
class TopicUser
  def self.notification_levels = { watching: 3, tracking: 2 }
end
class PostActionType
  def self.types = { like: 1 }
end

# -----------------------------------------------------------------------------
# Load targets resiliently
# -----------------------------------------------------------------------------

LOADED_TARGETS = {}

[
  [:search, "require_relative 'lib/search'"],
  [:pretty_text, "require_relative 'lib/pretty_text'"],
  [:file_helper, "require_relative 'lib/file_helper'"],
  [:final_destination, "require_relative 'lib/final_destination'"],
  [:url_helper, "require_relative 'lib/url_helper'"],
].each do |name, req|
  begin
    eval(req)
    LOADED_TARGETS[name] = true
  rescue LoadError, StandardError => e
    LOADED_TARGETS[name] = false
    $stderr.puts("[harness] Skipped #{name}: #{e.class}: #{e.message}")
  end
end

# -----------------------------------------------------------------------------
# Sinatra setup
# -----------------------------------------------------------------------------

configure do
  set :server, :webrick
  set :bind, "0.0.0.0"
  set :port, (ENV["PORT"] || 3001).to_i
end

helpers do
  def text_response(body)
    content_type "text/plain"
    body.is_a?(String) ? body : body.to_s
  end

  def json_body
    raw = request.body.read
    raw.nil? || raw.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def safe_call
    yield
  rescue => e
    status 500
    text_response("#{e.class}: #{e.message}")
  end
end

get "/health" do
  text_response("ok")
end

# -----------------------------------------------------------------------------
# Search targets
# -----------------------------------------------------------------------------

if LOADED_TARGETS[:search]
  get "/harness/search-ts-query" do
    safe_call do
      text_response(Search.ts_query(term: params["term"], ts_config: params["ts_config"]).to_s)
    end
  end

  get "/harness/search-to-tsquery" do
    safe_call do
      text_response(
        Search.to_tsquery(
          ts_config: params["ts_config"],
          term: params["term"],
          joiner: params["joiner"],
        ).to_s,
      )
    end
  end

  get "/harness/search-prepare-data" do
    safe_call do
      purpose = params["purpose"]
      purpose = purpose.to_sym if purpose.present?
      text_response(Search.prepare_data(params["search_data"], purpose).to_s)
    end
  end

  get "/harness/search-clean-term" do
    safe_call { text_response(Search.clean_term(params["term"]).to_s) }
  end

  get "/harness/search-word-to-date" do
    safe_call { text_response(Search.word_to_date(params["str"]).inspect) }
  end
end

# -----------------------------------------------------------------------------
# PrettyText targets
# -----------------------------------------------------------------------------

if LOADED_TARGETS[:pretty_text]
  post "/harness/prettytext-cook" do
    safe_call do
      payload = json_body
      text_response(PrettyText.cook(payload["raw"], payload["opts"] || {}).to_s)
    end
  end

  post "/harness/prettytext-markdown" do
    safe_call do
      payload = json_body
      text_response(PrettyText.markdown(payload["text"], payload["opts"] || {}).to_s)
    end
  end

  post "/harness/prettytext-extract-links" do
    safe_call do
      payload = json_body
      links = PrettyText.extract_links(payload["html"]).map(&:inspect).join("\n")
      text_response(links)
    end
  end

  post "/harness/prettytext-format-for-email" do
    safe_call do
      payload = json_body
      text_response(PrettyText.format_for_email(payload["html"], payload["post"]).to_s)
    end
  end
end

# -----------------------------------------------------------------------------
# FileHelper target
# -----------------------------------------------------------------------------

if LOADED_TARGETS[:file_helper]
  post "/harness/filehelper-sanitize-filename" do
    safe_call do
      payload = json_body
      text_response(FileHelper.sanitize_filename(payload["filename"]).to_s)
    end
  end
end

# -----------------------------------------------------------------------------
# FinalDestination target
# -----------------------------------------------------------------------------

if LOADED_TARGETS[:final_destination]
  get "/harness/finaldestination-validate-uri-format" do
    safe_call do
      text_response(FinalDestination.new(params["url"]).validate_uri_format.to_s)
    end
  end
end

# -----------------------------------------------------------------------------
# UrlHelper targets
# -----------------------------------------------------------------------------

if LOADED_TARGETS[:url_helper]
  get "/harness/urlhelper-normalized-encode" do
    safe_call { text_response(UrlHelper.normalized_encode(params["uri"]).to_s) }
  end

  get "/harness/urlhelper-cook-url" do
    safe_call do
      secure = params["secure"] == "true"
      local = params.key?("local") ? (params["local"] == "true") : nil
      text_response(UrlHelper.cook_url(params["url"], secure: secure, local: local).to_s)
    end
  end
end

run! if app_file == $0
