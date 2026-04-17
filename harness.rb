# frozen_string_literal: true

require "sinatra"
require "json"
require "uri"
require "cgi"
require "stringio"
require "tempfile"

begin
  require "active_support/all"
rescue LoadError
end

begin
  require "addressable/uri"
rescue LoadError
end

# Minimal compatibility shims for tier-1 harnessing without full framework boot.
module SiteSetting
  class << self
    def method_missing(name, *args, &block)
      defaults = {
        search_ignore_accents: false,
        default_locale: "en",
        search_tokenize_chinese: false,
        search_tokenize_japanese: false,
        search_page_size: 50,
        search_default_sort_order: 0,
        search_prefer_recent_posts: false,
        search_recent_posts_size: 100,
        search_recent_regular_posts_offset_post_id: 0,
        search_ranking_weights: nil,
        search_ranking_normalization: 0,
        prioritize_exact_search_title_match: false,
        tagging_enabled: true,
        max_tag_search_results: 25,
        secure_uploads: false,
        secure_uploads?: false,
        login_required: false,
        prevent_anons_from_downloading_files: false,
        content_localization_enabled: false,
        use_pg_headlines_for_excerpt: false,
        hide_user_profiles_from_public: false,
        enable_names: true,
        enable_listing_suspended_users_on_search: true,
        search_max_indexed_word_length: 20,
        max_duplicate_search_index_terms: 5,
        max_image_size_kb: 5120,
        max_image_megapixels: 50,
        "ImageQuality.png_to_jpg_quality": 80,
        "ImageQuality.recompress_original_jpg_quality": 80,
        video_thumbnails_enabled: false,
        strip_image_metadata: false,
      }
      return defaults[name] if defaults.key?(name)
      return defaults[name.to_s.chomp("?").to_sym] if defaults.key?(name.to_s.chomp("?").to_sym)
      nil
    end
  end
end

module Discourse
  def self.base_path = ""
  def self.asset_host = nil
  def self.base_url_no_prefix = "http://localhost:3001"
  def self.store
    @store ||= Struct.new(:external?) do
      def has_been_uploaded?(_url) = false
      def cdn_url(url) = url
      def upload_path = "uploads"
    end.new(false)
  end
end

module Rails
  def self.application
    @app ||= Struct.new(:routes).new(Struct.new(:recognize_path).new(->(_path) { nil }))
  end

  def self.logger
    @logger ||= Logger.new($stdout)
  end
end

module RailsMultisite
  module ConnectionManagement
    def self.current_db = "default"
  end
end

module DiscourseTagging
  def self.clean_tag(q) = q.to_s.strip
  def self.hidden_tag_names(_guardian) = []
  def self.filter_allowed_tags(*)
    [[], {}]
  end

  def self.filter_visible(scope, *_args)
    scope
  end
end

module TagsController
  def self.tag_counts_json(tags, _guardian)
    tags
  end
end

module Service
  module Base
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def params(&block); end
      def model(*args); end
      def step(*args); end
      def only_if(*args, &block); end
    end
  end
end

class Guardian
  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def can_see_private_messages?(_id) = true
  def can_lazy_load_categories? = false
  def can_see?(_obj) = true
  def can_see_unlisted_topics? = true
  def can_see_tag?(_tag) = true
  def allowed_category_ids = []
  def is_admin? = false
  def can_see_whispers? = false
end

class UploadedFile
  attr_accessor :path

  def initialize(path)
    @path = path
  end

  def close
  end

  def close!
  end

  def rewind
  end

  def respond_to_missing?(name, include_private = false)
    [:close!, :close, :rewind].include?(name) || super
  end
end

# Load targets with minimal bootstrapping.
require_relative "lib/search"
require_relative "lib/url_helper"
require_relative "app/services/wildcard_url_checker"
require_relative "lib/file_helper"
require_relative "lib/final_destination"
require_relative "lib/upload_creator"
require_relative "app/services/search_indexer"
require_relative "app/services/tags/search"

set :bind, "0.0.0.0"
set :port, (ENV["PORT"] || "3001").to_i

before do
  content_type "text/plain"
end

get "/health" do
  status 200
  "ok"
end

def bool_param(v)
  return false if v.nil?
  return v if v == true || v == false
  %w[true 1 yes on].include?(v.to_s.downcase)
end

def parse_json_param(value)
  return value if value.nil? || value.is_a?(Hash) || value.is_a?(Array)
  JSON.parse(value)
rescue JSON::ParserError
  value
end

def call_and_render
  result = yield
  if result.is_a?(String)
    result
  elsif result.nil?
    ""
  else
    JSON.generate(result)
  end
rescue => e
  status 500
  "#{e.class}: #{e.message}"
end

get "/harness/clean_term" do
  call_and_render { Search.clean_term(params["term"]) }
end

get "/harness/prepare_data" do
  call_and_render { Search.prepare_data(params["search_data"].to_s, params["purpose"]&.to_sym) }
end

get "/harness/word_to_date" do
  call_and_render { Search.word_to_date(params["str"].to_s)&.to_s }
end

get "/harness/is_valid_url" do
  call_and_render { UrlHelper.is_valid_url?(params["url"].to_s) }
end

get "/harness/normalized_encode" do
  call_and_render { UrlHelper.normalized_encode(params["uri"].to_s) }
end

get "/harness/check_url" do
  call_and_render { WildcardUrlChecker.check_url(params["url"].to_s, params["url_to_check"].to_s) }
end

post "/harness/clean_filename" do
  call_and_render { FileHelper.clean_filename(params["filename"].to_s) }
end

post "/harness/is_inline_safe" do
  call_and_render { FileHelper.is_inline_safe?(params["filename"].to_s) }
end

post "/harness/sanitize_filename" do
  call_and_render { FileHelper.sanitize_filename(params["filename"].to_s) }
end

get "/harness/cook_url" do
  call_and_render do
    UrlHelper.cook_url(
      params["url"].to_s,
      secure: bool_param(params["secure"]),
      local: params.key?("local") ? bool_param(params["local"]) : nil,
    )
  end
end

get "/harness/download" do
  call_and_render do
    FileHelper.download(
      params["url"].to_s,
      max_file_size: params["max_file_size"].to_i,
      tmp_file_name: params["tmp_file_name"].to_s,
    )&.path
  end
end

get "/harness/resolve" do
  call_and_render { FinalDestination.resolve(params["url"].to_s)&.to_s }
end

post "/harness/create_for" do
  call_and_render do
    file_path = params["file"].to_s
    file = UploadedFile.new(file_path)
    creator = UploadCreator.new(file, params["filename"].to_s)
    creator.create_for(params["user_id"].to_i).inspect
  end
end

post "/harness/update_index" do
  call_and_render do
    SearchIndexer.update_index(
      table: params["table"].to_s,
      id: params["id"].to_i,
      a_weight: params["a_weight"],
      b_weight: params["b_weight"],
    )
    "ok"
  end
end

get "/harness/search_tags" do
  call_and_render do
    guardian = Guardian.new
    raw_params = parse_json_param(params["params"] || "{}")
    Tags::Search.call(guardian: guardian, params: raw_params).inspect
  end
end

run! if __FILE__ == $PROGRAM_NAME
