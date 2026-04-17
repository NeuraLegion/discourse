# frozen_string_literal: true

require "json"
require "logger"
require "ostruct"
require "pathname"
require "uri"
require "open-uri"
require "yaml"
require "cgi"
require "set"
require "tempfile"
require "tmpdir"
require "sinatra/base"
require "net/http"

APP_ROOT = "/app"

$stdout.sync = true
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

def safe_require(path)
  require path
  true
rescue LoadError, StandardError => e
  LOGGER.warn("Failed to require #{path}: #{e.class}: #{e.message}")
  false
end

def safe_require_relative(path)
  require_relative path
  true
rescue LoadError, StandardError => e
  LOGGER.warn("Failed to require_relative #{path}: #{e.class}: #{e.message}")
  false
end

# -----------------------------------------------------------------------------
# Minimal core extensions required by the target files.
# -----------------------------------------------------------------------------

class Numeric
  def minute = self * 60
  def minutes = self * 60
  def hour = self * 3600
  def hours = self * 3600
  def day = self * 86_400
  def days = self * 86_400
  def week = self * 7 * 86_400
  def weeks = self * 7 * 86_400
  def megabyte = self * 1024 * 1024
  def megabytes = self * 1024 * 1024
end

class Object
  def blank?
    return true if nil?
    return !!empty? if respond_to?(:empty?)
    false
  end

  def present?
    !blank?
  end

  def presence
    present? ? self : nil
  end

  def with_indifferent_access
    self
  end
end

class NilClass
  def blank? = true
end

class FalseClass
  def blank? = true
end

class TrueClass
  def blank? = false
end

class String
  def blank?
    strip.empty?
  end

  def truncate(max, omission: "...")
    return self if length <= max
    return "" if max <= 0
    cut = max - omission.length
    cut = 0 if cut < 0
    self[0, cut] + omission
  end

  def parameterize
    s = dup
    begin
      s = s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
    rescue StandardError
    end
    s.downcase.gsub(/[^a-z0-9\-_]+/, "-").gsub(/-+/, "-").gsub(/\A-|-+\z/, "")
  end

  def starts_with?(*prefixes)
    start_with?(*prefixes)
  end
end

class Array
  def self.wrap(obj)
    return [] if obj.nil?
    return obj if obj.is_a?(Array)
    [obj]
  end

  def blank?
    empty?
  end

  def exclude?(value)
    !include?(value)
  end
end

class Hash
  def with_indifferent_access
    IndifferentHash.new(self)
  end

  def deep_symbolize_keys!
    keys.each do |k|
      v = delete(k)
      nk = k.respond_to?(:to_sym) ? k.to_sym : k

      if v.is_a?(Hash)
        v.deep_symbolize_keys!
      elsif v.is_a?(Array)
        v.each { |e| e.deep_symbolize_keys! if e.is_a?(Hash) }
      end

      self[nk] = v
    end
    self
  end

  def except!(*keys_to_remove)
    keys_to_remove.each { |k| delete(k) }
    self
  end

  def slice!(*allowed)
    allowed_set = allowed.to_set
    keys.each { |k| delete(k) unless allowed_set.include?(k) }
    self
  end
end

class IndifferentHash < Hash
  def initialize(source = {})
    super()
    update(source)
  end

  def [](key)
    super(convert_key(key))
  end

  def []=(key, value)
    super(convert_key(key), convert_value(value))
  end

  def key?(key)
    super(convert_key(key))
  end

  def fetch(key, *args, &block)
    super(convert_key(key), *args, &block)
  end

  def update(other)
    other.each_pair { |k, v| self[k] = v }
    self
  end

  private

  def convert_key(key)
    key.is_a?(String) ? key.to_sym : key
  end

  def convert_value(value)
    case value
    when Hash
      IndifferentHash.new(value)
    when Array
      value.map { |v| convert_value(v) }
    else
      value
    end
  end
end

# -----------------------------------------------------------------------------
# Framework shims
# -----------------------------------------------------------------------------

unless defined?(Rails)
  module Rails
    class << self
      def root
        Pathname.new(APP_ROOT)
      end

      def logger
        LOGGER
      end

      def env
        "test"
      end

      def application
        @application ||= begin
          routes =
            Class.new do
              def recognize_path(_path)
                nil
              end
            end.new

          Struct.new(:routes).new(routes)
        end
      end
    end
  end
end

unless defined?(Discourse)
  module Discourse
    def self.cache
      @cache ||= begin
        Class.new do
          def initialize
            @data = {}
          end

          def read(k)
            @data[k]
          end

          def write(k, v, **_opts)
            @data[k] = v
            true
          end

          def delete(k)
            @data.delete(k)
            true
          end

          def fetch(k, **_opts)
            return @data[k] if @data.key?(k)
            @data[k] = yield
          end
        end.new
      end
    end

    def self.redis
      @redis ||= begin
        Class.new do
          def initialize
            @data = {}
          end

          def get(k)
            @data[k]
          end

          def setex(k, _ttl, v)
            @data[k] = v
            true
          end

          def del(k)
            @data.delete(k)
            true
          end

          def without_namespace
            self
          end
        end.new
      end
    end

    def self.route_for(_url) = nil
    def self.base_url = "http://localhost:3001"
    def self.base_url_no_prefix = "http://localhost:3001"
    def self.base_path = ""
    def self.asset_host = nil

    def self.store
      @store ||= begin
        Class.new do
          def has_been_uploaded?(_url) = false
          def external? = false
          def upload_path = "uploads"
          def cdn_url(url) = url
        end.new
      end
    end

    class InvalidParameters < StandardError
      def initialize(param = nil)
        super(param ? "Invalid parameter: #{param}" : "Invalid parameters")
      end
    end
  end
end

unless defined?(RailsMultisite)
  module RailsMultisite
    module ConnectionManagement
      def self.current_db = "default"
    end
  end
end

unless defined?(SiteSetting)
  module SiteSetting
    def self.method_missing(name, *_args)
      case name
      when :enable_inline_onebox_on_all_domains then false
      when :allowed_inline_onebox_domains then nil
      when :block_onebox_on_redirect then false
      when :inline_onebox_user_agent then nil
      when :force_get_hosts then ""
      when :force_custom_user_agent_hosts then ""
      when :allowed_onebox_iframes then ""
      when :allowed_iframes then ""
      when :github_onebox_access_tokens then nil
      when :onebox_locale then nil
      when :default_locale then "en"
      when :slug_generation_method then :ascii
      when :secure_uploads then false
      when :login_required then false
      when :prevent_anons_from_downloading_files then false
      when :strip_image_metadata then false
      when :allow_users_to_hide_profile then false
      when :enable_names then false
      when :post_onebox_maxlength then 200
      when :facebook_app_access_token then nil
      when :disable_onebox_media_download_controls then false
      else
        nil
      end
    end

    def self.respond_to_missing?(_name, _include_private = false)
      true
    end
  end
end

unless defined?(GlobalSetting)
  module GlobalSetting
    def self.hostname = "localhost"
  end
end

unless defined?(WordWatcher)
  module WordWatcher
    def self.censor_text(x) = x
    def self.censor(x) = x
  end
end

unless defined?(Emoji)
  module Emoji
    EMOJI_CODE_REGEXP = /$^/
    def self.gsub_emoji_to_unicode(s) = s
  end
end

unless defined?(PrettyText)
  module PrettyText
    def self.cook(s) = s
    def self.avatar_img(*_) = ""
    def self.unescape_emoji(s) = s
  end
end

unless defined?(Onebox)
  module Onebox
    class DomainChecker
      def self.is_blocked?(_host) = false
    end

    class Matcher
      def initialize(*); end
      def oneboxed = false
    end

    module Helpers
      def self.normalize_url_for_output(url) = url
      def self.sanitize(s) = s
    end

    module Engine
      def self.origins_to_regexes(_o) = []
      def self.all_iframe_origins = []
    end

    module SanitizeConfig
      DISCOURSE_ONEBOX = nil
    end

    class << self
      def preview(*)
        Struct.new(:errors, :verified_data) do
          def to_s = ""
          def placeholder_html = ""
        end.new({}, {})
      end
    end
  end
end

unless defined?(FinalDestination)
  class FinalDestination
    class SSRFError < StandardError; end
    class UrlEncodingError < StandardError; end

    def initialize(url, **_opts)
      @url = url
      @uri = URI.parse(url)
      @status = :resolved
      @status_code = nil
    rescue URI::InvalidURIError
      @uri = nil
      @status = :invalid_address
      @status_code = nil
    end

    def get
      response =
        Class.new do
          def code = "200"
          def content_type = "text/plain"
          def [](key)
            return "text/plain" if key.to_s.downcase == "content-type"
            nil
          end
        end.new

      catch(:done) do
        yield(response, "", @uri)
      end
    end

    def resolve = @uri
    attr_reader :status, :status_code

    def hostname
      @uri&.host || "localhost"
    end

    def content_type = "text/plain"
    def cookie = nil
  end
end

unless defined?(MiniMime)
  module MiniMime
    def self.lookup_by_content_type(_ct)
      Struct.new(:extension).new("txt")
    end
  end
end

unless defined?(ThemeSetting)
  module ThemeSetting
    def self.types
      { enum: :enum, integer: :integer, string: :string, float: :float }
    end

    def self.guess_type(value)
      case value
      when Integer then :integer
      when Float then :float
      when String then :string
      when TrueClass, FalseClass then :string
      else nil
      end
    end
  end
end

safe_require "fastimage"
unless defined?(FastImage)
  class FastImage
    def self.size(_path) = [1, 1]
  end
end

unless defined?(RemoteTheme)
  module RemoteTheme
    def self.create_upload(*)
      errors =
        Class.new do
          def empty? = true
          def full_messages = []
        end.new
      Struct.new(:id, :errors).new(1, errors)
    end
  end
end

unless defined?(CategoryBadge)
  module CategoryBadge
    def self.html_for(*_) = ""
  end
end

unless defined?(Mustache)
  module Mustache
    def self.render(template, _args = {}) = template.to_s
  end
end

unless defined?(Guardian)
  class Guardian
    def initialize(*); end
    def can_see_post?(*_) = true
    def can_see_category?(*_) = true
    def can_see_topic?(*_) = true
  end
end

unless defined?(Post)
  class Post
    def self.types = { regular: 1, moderator_action: 2 }
  end
end

unless defined?(User)
  class User
    def self.find_by(*_) = nil
  end
end

unless defined?(Category)
  class Category
    def self.find_by(*_) = nil
    def self.find_by_slug_path_with_id(*_) = nil
  end
end

unless defined?(Topic)
  class Topic
    def self.find_by(*_) = nil
  end
end

unless defined?(I18n)
  module I18n
    def self.t(key, **_opts)
      key.to_s
    end

    def self.locale_available?(_key) = false
    def self.locale = :en

    def self.with_locale
      yield
    end
  end
end

unless defined?(ActiveSupport)
  module ActiveSupport
    module NumberHelper
      def self.number_to_human_size(n) = "#{n} bytes"
    end
  end
end

unless defined?(Addressable)
  module Addressable
    class URI
      module CharacterClasses
        UNRESERVED = "A-Za-z0-9\\-\\._~"
      end

      class << self
        def encode(url)
          ::URI::DEFAULT_PARSER.escape(url.to_s)
        end

        def unencode(url)
          ::URI::DEFAULT_PARSER.unescape(url.to_s)
        end

        def encode_component(component, _klass = nil)
          ::URI::DEFAULT_PARSER.escape(component.to_s)
        end

        def normalized_encode(url, _klass = nil)
          new(url)
        end
      end

      attr_accessor :scheme, :host, :path, :fragment

      def initialize(url)
        @original = url.to_s
        parsed = ::URI.parse(@original)
        @scheme = parsed.scheme
        @host = parsed.host
        @path = parsed.path
        @fragment = parsed.fragment
      rescue ::URI::InvalidURIError
        @scheme = nil
        @host = nil
        @path = nil
        @fragment = nil
      end

      def to_s
        if @original && !@original.empty?
          out = @original.dup
          out = out.sub(/\#.*\z/, "")
          out += "##{@fragment}" if @fragment
          out
        else
          ""
        end
      end
    end

    module IDNA
      def self.to_ascii(host)
        host.to_s
      end
    end
  end
end

unless defined?(HTMLEntities)
  class HTMLEntities
    def encode(str, *_args) = str.to_s
    def decode(str) = str.to_s
  end
end

safe_require "pathname"
safe_require "nokogiri"
safe_require "loofah"
safe_require "mini_mime"

loaded = {}

loaded["FileHelper"] = safe_require_relative "lib/file_helper"
loaded["InlineOneboxer"] = safe_require_relative "lib/inline_oneboxer"

loaded["Oneboxer"] =
  begin
    oneboxer_path = File.join(APP_ROOT, "lib/oneboxer.rb")
    src = File.read(oneboxer_path)
    src.sub!(
      /Dir\["\#\{Rails\.root\}\/lib\/onebox\/engine\/\*_onebox\.rb"\]\.sort\.each\s*\{\s*\|f\|\s*require f\s*\}/,
      "# engine autoload disabled in harness",
    )
    TOPLEVEL_BINDING.eval(src, oneboxer_path)
    true
  rescue LoadError, StandardError => e
    LOGGER.warn("Failed to load lib/oneboxer.rb: #{e.class}: #{e.message}")
    false
  end

loaded["RetrieveTitle"] = safe_require_relative "lib/retrieve_title"
loaded["UrlHelper"] = safe_require_relative "lib/url_helper"
loaded["Slug"] = safe_require_relative "lib/slug"
loaded["ThemeTranslationParser"] = safe_require_relative "lib/theme_translation_parser"
loaded["ThemeSettingsParser"] = safe_require_relative "lib/theme_settings_parser"
loaded["ThemeScreenshotsHandler"] = safe_require_relative "lib/theme_screenshots_handler"

class HarnessApp < Sinatra::Base
  LOADED_MAP = loaded

  set :bind, "0.0.0.0"
  set :port, ENV.fetch("PORT", "3001").to_i
  set :loaded_map, LOADED_MAP

  before do
    content_type "text/plain"
  end

  helpers do
    def loaded?(name)
      settings.loaded_map[name]
    end

    def parse_json_body
      request.body.rewind
      body = request.body.read
      body.nil? || body.empty? ? {} : JSON.parse(body)
    rescue JSON::ParserError => e
      halt 400, "#{e.class}: #{e.message}"
    end
  end

  error do
    e = env["sinatra.error"]
    status 500
    content_type "text/plain"
    "#{e.class}: #{e.message}"
  end

  get "/health" do
    "ok"
  end

  post "/harness/filehelper-download" do
    halt 501, "FileHelper not loaded" unless loaded?("FileHelper")
    p = parse_json_body

    tmp = FileHelper.download(
      p["url"],
      max_file_size: p["max_file_size"] || 1_048_576,
      tmp_file_name: p["tmp_file_name"] || "harness-download",
      follow_redirect: !!p["follow_redirect"],
      read_timeout: p["read_timeout"] || 5,
      skip_rate_limit: !!p["skip_rate_limit"],
      verbose: !!p["verbose"],
      validate_uri: p.key?("validate_uri") ? !!p["validate_uri"] : true,
      retain_on_max_file_size_exceeded: !!p["retain_on_max_file_size_exceeded"],
      include_port_in_host_header: !!p["include_port_in_host_header"],
      extra_headers: p["extra_headers"] || {},
    )

    if tmp
      data = tmp.read
      tmp.close!
      data.to_s
    else
      ""
    end
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  get "/harness/inlineoneboxer-lookup" do
    halt 501, "InlineOneboxer not loaded" unless loaded?("InlineOneboxer")

    url = params["url"]
    opts = params["opts"] ? JSON.parse(params["opts"]) : {}
    res = InlineOneboxer.lookup(url, opts)
    res.nil? ? "" : res.to_json
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  get "/harness/oneboxer-preview" do
    halt 501, "Oneboxer not loaded" unless loaded?("Oneboxer")

    url = params["url"]
    options = params["options"] ? JSON.parse(params["options"]) : {}
    res = Oneboxer.preview(url, options.with_indifferent_access)
    res.to_s
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  get "/harness/retrievetitle-crawl" do
    halt 501, "RetrieveTitle not loaded" unless loaded?("RetrieveTitle")

    url = params["url"]
    max_redirects = params.key?("max_redirects") ? params["max_redirects"].to_i : nil
    headers = params["headers"] ? JSON.parse(params["headers"]) : {}
    initial_https_redirect_ignore_limit =
      params.key?("initial_https_redirect_ignore_limit") ? params["initial_https_redirect_ignore_limit"] == "true" : false

    res = RetrieveTitle.crawl(
      url,
      max_redirects: max_redirects,
      initial_https_redirect_ignore_limit: initial_https_redirect_ignore_limit,
      headers: headers,
    )
    res.to_s
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  get "/harness/urlhelper-normalized-encode" do
    halt 501, "UrlHelper not loaded" unless loaded?("UrlHelper")
    UrlHelper.normalized_encode(params["uri"]).to_s
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  post "/harness/slug-for" do
    halt 501, "Slug not loaded" unless loaded?("Slug")
    p = parse_json_body

    method_value = p["method"]
    kwargs = {}
    kwargs[:method] = method_value.to_sym if method_value.is_a?(String)
    kwargs[:method] = method_value if method_value.is_a?(Symbol)

    Slug.for(
      p["string"].to_s,
      p["default"] || "topic",
      p["max_length"] || 255,
      **kwargs,
    ).to_s
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  post "/harness/themetranslationparser-load" do
    halt 501, "ThemeTranslationParser not loaded" unless loaded?("ThemeTranslationParser")
    p = parse_json_body

    field_hash = p["setting_field"] || {}
    setting_field = OpenStruct.new(field_hash)
    res = ThemeTranslationParser.new(setting_field, internal: !!p["internal"]).load
    res.to_json
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  post "/harness/themesettingsparser-load" do
    halt 501, "ThemeSettingsParser not loaded" unless loaded?("ThemeSettingsParser")
    p = parse_json_body

    field_hash = p["setting_field"] || {}
    setting_field = OpenStruct.new(field_hash)
    out = []

    ThemeSettingsParser.new(setting_field).load do |setting, value, type, opts|
      out << { setting: setting, value: value, type: type, opts: opts }
    end

    out.to_json
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end

  post "/harness/themescreenshotshandler-parse-screenshots-as-theme-fields-" do
    halt 501, "ThemeScreenshotsHandler not loaded" unless loaded?("ThemeScreenshotsHandler")
    p = parse_json_body

    screenshots = p["screenshots"] || []

    importer = Object.new
    importer_data = p["theme_importer"] || {}
    importer.define_singleton_method(:real_path) do |rel|
      importer_data["paths"]&.[](rel) || rel
    end

    theme = Object.new
    recorded = []
    theme.define_singleton_method(:set_field) do |**kwargs|
      recorded << kwargs
      kwargs
    end

    handler = ThemeScreenshotsHandler.new(theme)
    res = handler.parse_screenshots_as_theme_fields!(screenshots, importer)
    res.to_json
  rescue => e
    status 500
    "#{e.class}: #{e.message}"
  end
end

HarnessApp.run!
