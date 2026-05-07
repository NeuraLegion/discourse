# frozen_string_literal: true

require "json"
require "logger"
require "sinatra/base"

$stdout.sync = true
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

def safe_require(path)
  require path
  true
rescue LoadError, StandardError => e
  LOGGER.warn("Failed to load #{path}: #{e.class}: #{e.message}")
  false
end

def plain_text(obj)
  case obj
  when nil
    ""
  when String
    obj
  when Array
    obj.map { |v| plain_text(v) }.join("\n")
  when Hash
    obj.to_json
  else
    if obj.respond_to?(:to_h)
      obj.to_h.to_json
    elsif obj.respond_to?(:to_json)
      obj.to_json
    else
      obj.to_s
    end
  end
end

def call_target
  yield
rescue => e
  [500, { "Content-Type" => "text/plain" }, ["#{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"]]
end

safe_require "bundler/setup" rescue nil
safe_require "active_support/all" rescue nil
safe_require "uri" rescue nil
safe_require "set" rescue nil
safe_require "nokogiri" rescue nil
safe_require "erb" rescue nil
safe_require "open-uri" rescue nil
safe_require "final_destination" rescue nil
safe_require "mini_mime" rescue nil
safe_require "addressable/uri" rescue nil
safe_require "addressable/idna" rescue nil
safe_require "tempfile" rescue nil
safe_require "cgi" rescue nil
safe_require "loofah" rescue nil
safe_require "pp" rescue nil

Dir.chdir("/app") if Dir.exist?("/app")
$LOAD_PATH.unshift("/app") unless $LOAD_PATH.include?("/app")
$LOAD_PATH.unshift("/app/lib") unless $LOAD_PATH.include?("/app/lib")

# Minimal framework/application stubs so tier-1 helpers can run without full Rails boot.
unless defined?(Rails)
  module Rails
    def self.root
      Pathname.new("/app")
    end

    def self.logger
      LOGGER
    end

    def self.env
      ActiveSupport::StringInquirer.new(ENV["RAILS_ENV"] || "development")
    end

    def self.configuration
      @configuration ||= Struct.new(:action_controller).new(
        Struct.new(:asset_host).new(nil),
      )
    end

    def self.application
      @application ||= begin
        routes = Object.new
        def routes.recognize_path(path)
          { path: path }
        end

        Struct.new(:routes).new(routes)
      end
    end
  end
end

unless defined?(GlobalSetting)
  module GlobalSetting
    def self.method_missing(_name, *_args, &_blk)
      nil
    end

    def self.respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end

unless defined?(SiteSetting)
  module SiteSetting
    class UploadSettings
      def self.enable_s3_uploads
        false
      end

      def self.s3_cdn_url
        nil
      end
    end

    def self.search_page_size
      20
    end

    def self.default_locale
      "en"
    end

    def self.search_ignore_accents
      false
    end

    def self.search_tokenize_chinese
      false
    end

    def self.search_tokenize_japanese
      false
    end

    def self.min_search_term_length
      3
    end

    def self.search_default_sort_order
      0
    end

    def self.log_search_queries?
      false
    end

    def self.secure_uploads
      false
    end

    def self.secure_uploads?
      secure_uploads
    end

    def self.login_required
      false
    end

    def self.login_required?
      login_required
    end

    def self.prevent_anons_from_downloading_files
      false
    end

    def self.prevent_anons_from_downloading_files?
      prevent_anons_from_downloading_files
    end

    def self.add_rel_nofollow_to_user_content
      false
    end

    def self.block_hotlinked_media
      false
    end

    def self.block_hotlinked_media_exceptions
      ""
    end

    def self.exclude_rel_nofollow_domains
      ""
    end

    def self.enable_mentions
      false
    end

    def self.enable_emoji?
      false
    end

    def self.enable_emoji
      false
    end

    def self.enable_emoji_shortcuts
      false
    end

    def self.enable_inline_emoji_translation
      false
    end

    def self.emoji_set
      "apple"
    end

    def self.external_emoji_url
      nil
    end

    def self.avatar_sizes
      "20|25|32|45|60|120"
    end

    def self.client_settings_json
      "{}"
    end

    def self.method_missing(name, *_args, &_blk)
      return UploadSettings if name == :Upload
      false
    end

    def self.respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end

unless defined?(Discourse)
  module Discourse
    class InvalidParameters < StandardError; end
    class InvalidAccess < StandardError; end

    def self.readonly_mode?
      false
    end

    def self.base_path
      ""
    end

    def self.current_hostname
      "localhost"
    end

    def self.base_url_no_prefix
      "http://localhost"
    end

    def self.base_url
      "#{base_url_no_prefix}#{base_path}"
    end

    def self.asset_host
      nil
    end

    def self.route_for(uri)
      unless uri.is_a?(URI)
        uri = URI(uri)
      end

      path = +(uri.path || "")
      if !uri.host || uri.host == current_hostname
        path.slice!(base_path) if base_path.present? && path.start_with?(base_path)
        Rails.application.routes.recognize_path(path)
      end
    rescue
      nil
    end

    def self.store
      @store ||= begin
        store = Object.new

        def store.has_been_uploaded?(_url)
          false
        end

        def store.cdn_url(url)
          url
        end

        def store.external?
          false
        end

        def store.upload_path
          "uploads"
        end

        def store.absolute_base_url
          "http://localhost/uploads"
        end

        store
      end
    end

    def self.plugins
      []
    end
  end
end

unless defined?(Guardian)
  safe_require "./lib/guardian"
end

unless defined?(Guardian)
  class Guardian
    class AnonymousUser
      def blank?
        true
      end

      def anonymous?
        true
      end

      def admin?
        false
      end

      def staff?
        false
      end

      def moderator?
        false
      end

      def silenced?
        false
      end

      def staged?
        false
      end

      def secure_category_ids
        []
      end

      def groups
        []
      end

      def whisperer?
        false
      end

      def in_any_groups?(_group_ids)
        false
      end
    end

    def initialize(user = nil, _request = nil)
      @user = user || AnonymousUser.new
    end

    def user
      @user.is_a?(AnonymousUser) ? nil : @user
    end

    def can_lazy_load_categories?
      false
    end

    def can_see_private_messages?(_user_id)
      false
    end

    def is_admin?
      false
    end
  end
end

unless defined?(ExcerptParser)
  safe_require "./lib/excerpt_parser"
end

loaded = {}
loaded["search"] = safe_require("./lib/search")
loaded["pretty_text"] = safe_require("./lib/pretty_text")
loaded["file_helper"] = safe_require("./lib/file_helper")
loaded["url_helper"] = safe_require("./lib/url_helper")

class HarnessApp < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, (ENV["PORT"] || "3001").to_i
  set :show_exceptions, false
  set :raise_errors, true

  before do
    content_type "text/plain"
  end

  get "/health" do
    "ok"
  end

  get "/harness/search-execute" do
    call_target do
      term = params["term"].to_s
      opts = params["opts"] ? JSON.parse(params["opts"], symbolize_names: true) : {}
      opts[:guardian] ||= Guardian.new
      result = Search.execute(term, opts)
      plain_text(result)
    end
  end

  get "/harness/search-prepare-data" do
    call_target do
      search_data = params["search_data"].to_s
      purpose = params["purpose"]
      purpose = purpose.to_sym if purpose && !purpose.empty?
      plain_text(Search.prepare_data(search_data, purpose))
    end
  end

  post "/harness/prettytext-cook" do
    call_target do
      raw = params["raw"].to_s
      opts = params["opts"] ? JSON.parse(params["opts"], symbolize_names: true) : {}
      plain_text(PrettyText.cook(raw, opts))
    end
  end

  post "/harness/prettytext-excerpt" do
    call_target do
      html = params["html"].to_s
      max_length = params["max_length"].to_i
      options = params["options"] ? JSON.parse(params["options"], symbolize_names: true) : {}
      plain_text(PrettyText.excerpt(html, max_length, options))
    end
  end

  post "/harness/prettytext-strip-links" do
    call_target do
      string = params["string"].to_s
      plain_text(PrettyText.strip_links(string))
    end
  end

  post "/harness/prettytext-extract-links" do
    call_target do
      html = params["html"].to_s
      result = PrettyText.extract_links(html)
      plain_text(
        result.map do |l|
          {
            url: l.url,
            is_quote: l.is_quote,
          }
        end.to_json,
      )
    end
  end

  post "/harness/prettytext-lookup-mentions" do
    call_target do
      names = params["names"] ? JSON.parse(params["names"]) : []
      user_id = params["user_id"].to_i
      kwargs = {}
      kwargs[:user_id] = user_id if user_id > 0
      plain_text(PrettyText.lookup_mentions(names, **kwargs))
    end
  end

  post "/harness/filehelper-download" do
    call_target do
      url = params["url"].to_s
      max_file_size = params["max_file_size"].to_i
      max_file_size = 1_048_576 if max_file_size <= 0
      tmp_file_name = params["tmp_file_name"].to_s
      tmp_file_name = "download" if tmp_file_name.empty?

      tmp = ::FileHelper.download(url, max_file_size: max_file_size, tmp_file_name: tmp_file_name)
      if tmp
        body = {
          path: tmp.path,
          size: File.size?(tmp.path),
          content: File.read(tmp.path, mode: "rb"),
        }
        plain_text(body)
      else
        plain_text("nil")
      end
    end
  end

  post "/harness/filehelper-sanitize-filename" do
    call_target do
      filename = params["filename"].to_s
      plain_text(::FileHelper.sanitize_filename(filename))
    end
  end

  get "/harness/urlhelper-is-valid-url-" do
    call_target do
      url = params["url"].to_s
      plain_text(UrlHelper.is_valid_url?(url).to_s)
    end
  end

  get "/harness/urlhelper-normalized-encode" do
    call_target do
      uri = params["uri"].to_s
      plain_text(UrlHelper.normalized_encode(uri))
    end
  end

  get "/harness/urlhelper-rails-route-from-url" do
    call_target do
      url = params["url"].to_s
      plain_text(UrlHelper.rails_route_from_url(url))
    end
  end

  get "/harness/urlhelper-cook-url" do
    call_target do
      url = params["url"].to_s
      secure = params["secure"] == "true" || params["secure"] == "1"
      local = if params.key?("local")
        params["local"] == "true" || params["local"] == "1"
      else
        nil
      end
      plain_text(UrlHelper.cook_url(url, secure: secure, local: local))
    end
  end

  error do
    e = env["sinatra.error"]
    status 500
    content_type "text/plain"
    "#{e.class}: #{e.message}"
  end
end

HarnessApp.run!
