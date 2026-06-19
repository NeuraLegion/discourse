# frozen_string_literal: true

require "json"
require "logger"
require "socket"
require "uri"
require "set"
require "tempfile"
require "webrick"
require "pathname"
require "time"
require "date"
require "net/http"
require "nokogiri"
require "openssl"
require "timeout"
require "stringio"

begin
  require "sinatra/base"
rescue LoadError
  require "rack"
end

# ---- Minimal ActiveSupport-ish shims ----
class Object
  def blank?
    respond_to?(:empty?) ? !!empty? : !self
  end

  def present?
    !blank?
  end

  def presence
    present? ? self : nil
  end

  def try(method_name = nil, *args, &block)
    return yield(self) if method_name.nil? && block
    return nil unless respond_to?(method_name)
    public_send(method_name, *args, &block)
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

  def present?
    !blank?
  end

  def presence
    present? ? self : nil
  end

  def starts_with?(*prefixes)
    start_with?(*prefixes)
  end

  def ends_with?(*suffixes)
    end_with?(*suffixes)
  end

  def truncate(max)
    return self if length <= max
    self[0, max]
  end

  def squish
    gsub(/\s+/, " ").strip
  end

  def squish!
    replace(squish)
  end

  def titlecase
    split(/\s+/).map { |w| w.capitalize }.join(" ")
  end
end

class Array
  def self.wrap(obj)
    return [] if obj.nil?
    obj.is_a?(Array) ? obj : [obj]
  end
end

class Hash
  def except(*keys)
    dup.tap { |h| keys.each { |k| h.delete(k) } }
  end
end

class Numeric
  def day = self
  def days = self
  def week = self * 7 * 24 * 60 * 60
  def weeks = self * 7 * 24 * 60 * 60
end

class Time
  def beginning_of_day
    Time.local(year, month, day)
  end

  def yesterday
    self - 86_400
  end

  def days_ago(n)
    self - (n.to_i * 86_400)
  end

  def beginning_of_week(_start_day = :monday)
    beginning_of_day - ((wday == 0 ? 6 : wday - 1) * 86_400)
  end

  def beginning_of_month
    Time.local(year, month, 1)
  end

  def months_ago(n)
    n = n.to_i
    y = year
    m = month - n
    while m <= 0
      m += 12
      y -= 1
    end
    Time.local(y, m, 1)
  end
end

class << Time
  def zone
    @zone ||= Object.new.tap do |z|
      def z.now
        Time.now
      end

      def z.parse(str)
        Time.parse(str)
      end
    end
  end
end

class Module
  def cattr_accessor(*names)
    names.each do |name|
      singleton_class.class_eval { attr_accessor name }
    end
  end
end

# ---- Minimal Rails-ish shims for Tier 1/2 loading ----
module Rails
  def self.root
    Pathname.new("/app")
  end

  def self.logger
    @logger ||= Logger.new($stdout)
  end

  def self.env
    @env ||= Struct.new(:test?).new(false)
  end

  def self.configuration
    @configuration ||= Struct.new(:action_controller).new(
      Struct.new(:asset_host).new(nil),
    )
  end

  def self.application
    routes_obj = Object.new
    routes_obj.define_singleton_method(:recognize_path) { |_path| {} }

    @application ||= Struct.new(:routes).new(routes_obj)
  end
end

module RailsMultisite
  module ConnectionManagement
    def self.current_db
      "default"
    end
  end
end

module Discourse
  def self.base_path = ""
  def self.base_url_no_prefix = "http://localhost:3001"
  def self.base_url = "http://localhost:3001"
  def self.asset_host = nil
  def self.readonly_mode? = false

  def self.store
    @store ||= Struct.new(:external?).new(false).tap do |s|
      def s.has_been_uploaded?(_url) = false
      def s.cdn_url(url) = url
      def s.upload_path = "uploads"
      def s.absolute_base_url = "http://localhost:3001"
    end
  end

  def self.redis
    @redis ||= Object.new.tap do |r|
      store = {}
      without_ns = Object.new
      without_ns.define_singleton_method(:get) { |k| store[k] }
      without_ns.define_singleton_method(:setex) { |k, _ttl, v| store[k] = v }
      without_ns.define_singleton_method(:del) { |k| store.delete(k) }
      r.define_singleton_method(:without_namespace) { without_ns }
    end
  end

  def self.cache
    @cache ||= Object.new.tap do |c|
      c.define_singleton_method(:fetch) do |_key, *_args|
        yield
      end
    end
  end

  def self.plugins
    []
  end
end

module SiteSetting
  module Upload
    def self.enable_s3_uploads = false
    def self.s3_cdn_url = nil
  end

  class << self
    def method_missing(name, *_args)
      s = name.to_s
      return false if s.end_with?("?")
      return false if s == "secure_uploads"
      return "" if s.end_with?("_url") || s.end_with?("_hosts") || s.include?("domains")
      return [] if s == "avatar_sizes"
      return "en" if s == "default_locale"
      return 3 if s == "min_search_term_length" || s == "search_page_size"
      return 0 if s.include?("length") || s.include?("size") || s.include?("count")
      nil
    end

    def respond_to_missing?(*)
      true
    end

    def defaults
      @defaults ||= Object.new.tap do |d|
        d.define_singleton_method(:get) { |_k, _l = nil| 3 }
      end
    end

    def client_settings_json = "{}"
  end
end

module Onebox
  module Helpers
    def self.user_agent
      "Mozilla/5.0"
    end
  end

  module DomainChecker
    def self.is_blocked?(_host)
      false
    end
  end
end

module GlobalSetting
  def self.method_missing(name, *_args)
    return "" if name.to_s.end_with?("_url")
    nil
  end

  def self.respond_to_missing?(*)
    true
  end
end

module Upload
  def self.secure_uploads_url_from_upload_url(url) = url
  def self.secure_uploads_url?(_url) = false
  def self.base62_sha1(s) = s
end

module PG
  class Connection
    def self.escape_string(s) = s.to_s.gsub("\\", "\\\\")
  end
end

begin
  require "addressable/uri"
  require "addressable/idna"
rescue LoadError
  module Addressable
    class IDNA
      def self.to_ascii(host) = host
    end

    module URI
      class InvalidURIError < StandardError; end

      module CharacterClasses
        UNRESERVED = /./
      end

      def self.encode(url)
        url.to_s
      end

      def self.unencode(url)
        url.to_s
      end

      def self.encode_component(str, _cc = nil)
        ::URI.encode_www_form_component(str.to_s)
      end

      def self.normalized_encode(url, _klass = nil)
        parsed = ::URI.parse(url.to_s)
        parsed
      rescue ::URI::Error
        raise InvalidURIError
      end
    end
  end
end

module Loofah
  class Scrubber
    def initialize(&block)
      @block = block
    end
  end

  def self.html5_fragment(html)
    Nokogiri::HTML5.fragment(html)
  end
end

module I18n
  def self.t(key) = key
end

module DB
  def self.query(*_args)
    []
  end
end

module SSRFDetector
  class DisallowedIpError < StandardError
  end

  def self.lookup_and_filter_ips(host)
    [host]
  end
end

module Excon
  def self.defaults
    @defaults ||= { middlewares: [] }
  end

  module Middleware
    class Decompress
    end
  end

  module Errors
    class Timeout < StandardError
    end

    class ExpectationFailed < StandardError
    end
  end

  Response = Struct.new(:status, :headers, :data)

  def self.head(*_args)
    raise Errors::Timeout
  end

  def self.get(*_args)
    raise Errors::Timeout
  end
end

class RateLimiter; end unless defined?(RateLimiter)

module MiniMime
  Lookup = Struct.new(:extension)

  def self.lookup_by_content_type(_ct)
    nil
  end
end

class Discourse::InvalidParameters < StandardError
  def initialize(*_args) = super("invalid parameters")
end

module FinalDestinationHTTPStub
  Response = Struct.new(:code, :content_type, :headers) do
    def [](key)
      headers[key]
    end

    def to_hash
      headers.each_with_object({}) { |(k, v), h| h[k.downcase] = Array.wrap(v) }
    end

    def read_body
      yield("") if block_given?
    end
  end

  class Session
    attr_accessor :read_timeout

    def request(_req)
      resp = Response.new("200", "text/plain", {})
      yield resp
    end

    def request_get(_path, _headers)
      resp = Response.new("200", "text/plain", {})
      yield resp
    end

    def finish
    end
  end

  class Get
    def initialize(_uri, _headers); end
  end

  def self.start(_host, _port, **_opts)
    session = Session.new
    if block_given?
      yield session
    else
      session
    end
  end
end

# ---- Preload stubs for absolute requires used by target files ----
$LOAD_PATH.unshift("/app/lib") unless $LOAD_PATH.include?("/app/lib")

# ---- Load targets resiliently ----
TARGETS = %w[
  lib/git_url.rb
  lib/url_helper.rb
  lib/search.rb
  lib/final_destination.rb
  lib/file_helper.rb
  lib/pretty_text.rb
]

def safe_require(path)
  require File.expand_path(path, "/app")
  true
rescue LoadError => e
  warn "[harness] failed to load #{path}: #{e.class}: #{e.message}"
  false
rescue Exception => e
  warn "[harness] failed to load #{path}: #{e.class}: #{e.message}"
  false
end

TARGETS.each { |path| safe_require(path) }

# FinalDestination depends on an HTTP adapter constant which the real app wires up.
# In the harness we provide a tiny Net::HTTP-compatible stub if the class loaded but
# did not define HTTP.
if defined?(::FinalDestination) && ::FinalDestination.is_a?(Class) &&
     !::FinalDestination.const_defined?(:HTTP)
  ::FinalDestination.const_set(:HTTP, FinalDestinationHTTPStub)
end

if !defined?(::FinalDestination) || !::FinalDestination.is_a?(Class)
  Object.send(:remove_const, :FinalDestination) if defined?(::FinalDestination)

  class FinalDestination
    HTTP = FinalDestinationHTTPStub

    def self.redis_https_key(domain)
      "HTTPS_DOMAIN_#{domain}"
    end

    def self.is_https_domain?(domain)
      Discourse.redis.without_namespace.get(redis_https_key(domain)).present?
    end

    def self.cache_https_domain(domain)
      Discourse.redis.without_namespace.setex(redis_https_key(domain), 1.day.to_i, "1")
    end

    def self.resolve(url, _opts = nil)
      url
    end

    def initialize(url, _opts = nil)
      @url = url
    end

    def get
      raise "Must specify block" unless block_given?
      yield(
        Struct.new(:code, :content_type).new("200", "text/plain"),
        "",
        URI.parse(@url),
      )
    end
  end
end

# ---- Web app ----
class HarnessApp
  def call(env)
    req = Rack::Request.new(env)

    begin
      case [req.request_method, req.path_info]
      when ["GET", "/health"]
        ok("ok")

      when ["GET", "/harness/giturl-normalize"]
        ok(GitUrl.normalize(req.params["url"].to_s))

      when ["POST", "/harness/filehelper-sanitize-filename"]
        params = request_params(req)
        ok(FileHelper.sanitize_filename(params["filename"].to_s))

      when ["GET", "/harness/urlhelper-is-valid-url-"]
        ok(UrlHelper.is_valid_url?(req.params["url"].to_s).to_s)

      when ["GET", "/harness/urlhelper-normalized-encode"]
        value =
          begin
            UrlHelper.normalized_encode(req.params["uri"].to_s)
          rescue URI::Error, Addressable::URI::InvalidURIError, ArgumentError
            ""
          end
        ok(value.to_s)

      when ["GET", "/harness/urlhelper-cook-url"]
        ok(
          UrlHelper.cook_url(
            req.params["url"].to_s,
            secure: truthy?(req.params["secure"]),
            local: parse_optional_bool(req.params["local"]),
          ).to_s,
        )

      when ["GET", "/harness/search-ts-config"]
        ok(Search.ts_config(req.params["locale"].presence || SiteSetting.default_locale).to_s)

      when ["GET", "/harness/search-clean-term"]
        ok(Search.clean_term(req.params["term"].to_s).to_s)

      when ["GET", "/harness/search-word-to-date"]
        value = Search.word_to_date(req.params["str"].to_s)
        ok(value.nil? ? "" : value.to_s)

      when ["GET", "/harness/search-prepare-data"]
        purpose =
          case req.params["purpose"].to_s
          when "", "nil", "null"
            nil
          when "topic", ":topic"
            :topic
          else
            req.params["purpose"].to_s
          end
        ok(Search.prepare_data(req.params["search_data"].to_s, purpose).to_s)

      when ["GET", "/harness/filehelper-download"]
        tmp =
          FileHelper.download(
            req.params["url"].to_s,
            max_file_size: (req.params["max_file_size"] || "1048576").to_i,
            tmp_file_name: (req.params["tmp_file_name"].presence || "harness"),
            follow_redirect: truthy?(req.params["follow_redirect"]),
            read_timeout: (req.params["read_timeout"] || "5").to_i,
            skip_rate_limit: truthy?(req.params["skip_rate_limit"]),
            verbose: truthy?(req.params["verbose"]),
            validate_uri: !falsy?(req.params["validate_uri"]),
            retain_on_max_file_size_exceeded: truthy?(req.params["retain_on_max_file_size_exceeded"]),
            include_port_in_host_header: truthy?(req.params["include_port_in_host_header"]),
            extra_headers: {},
          )
        if tmp
          body = tmp.read.to_s
          tmp.close!
          ok(body)
        else
          ok("")
        end

      when ["GET", "/harness/finaldestination-resolve"]
        result = FinalDestination.resolve(req.params["url"].to_s)
        ok(result.to_s)

      when ["GET", "/harness/finaldestination-is-https-domain-"]
        ok(FinalDestination.is_https_domain?(req.params["domain"].to_s).to_s)

      when ["POST", "/harness/prettytext-lookup-mentions"]
        params = request_params(req)
        names = parse_names_param(params["names"])
        user_id = params["user_id"].to_i
        ok(PrettyText.send(:lookup_mentions, names, user_id: user_id).to_json)

      when ["POST", "/harness/prettytext-add-rel-attributes-to-user-content"]
        params = request_params(req)
        html = params["doc"].to_s
        add_nofollow = truthy?(params["add_nofollow"])
        doc = Nokogiri::HTML5.fragment(html)
        PrettyText.add_rel_attributes_to_user_content(doc, add_nofollow)
        ok(doc.to_html)

      else
        [404, { "Content-Type" => "text/plain" }, ["not found"]]
      end
    rescue Exception => e
      [500, { "Content-Type" => "text/plain" }, ["#{e.class}: #{e.message}"]]
    end
  end

  def request_params(req)
    req.POST
  rescue
    req.params
  end

  def parse_names_param(raw)
    s = raw.to_s
    return [] if s.blank?

    begin
      parsed = JSON.parse(s)
      Array.wrap(parsed).map(&:to_s)
    rescue JSON::ParserError
      s.split(",").map(&:strip).reject(&:empty?)
    end
  end

  def parse_optional_bool(v)
    return nil if v.nil? || v.to_s == ""
    truthy?(v)
  end

  def truthy?(v)
    %w[1 true t yes y].include?(v.to_s.downcase)
  end

  def falsy?(v)
    %w[0 false f no n].include?(v.to_s.downcase)
  end

  def ok(body)
    [200, { "Content-Type" => "text/plain" }, [body.to_s]]
  end
end

app = HarnessApp.new
port = ENV.fetch("PORT", "3001").to_i

if defined?(Sinatra::Base)
  class App < Sinatra::Base
    set :bind, "0.0.0.0"
    set :port, ENV.fetch("PORT", "3001").to_i
    set :server, "webrick"

    before do
      content_type "text/plain"
    end

    helpers do
      def truthy?(v)
        %w[1 true t yes y].include?(v.to_s.downcase)
      end

      def falsy?(v)
        %w[0 false f no n].include?(v.to_s.downcase)
      end

      def parse_optional_bool(v)
        return nil if v.nil? || v.to_s == ""
        truthy?(v)
      end

      def parse_names_param(raw)
        s = raw.to_s
        return [] if s.blank?

        begin
          parsed = JSON.parse(s)
          Array.wrap(parsed).map(&:to_s)
        rescue JSON::ParserError
          s.split(",").map(&:strip).reject(&:empty?)
        end
      end
    end

    get("/health") { "ok" }

    get("/harness/giturl-normalize") do
      GitUrl.normalize(params["url"].to_s)
    end

    post("/harness/filehelper-sanitize-filename") do
      FileHelper.sanitize_filename(params["filename"].to_s)
    end

    get("/harness/urlhelper-is-valid-url-") do
      UrlHelper.is_valid_url?(params["url"].to_s).to_s
    end

    get("/harness/urlhelper-normalized-encode") do
      begin
        UrlHelper.normalized_encode(params["uri"].to_s).to_s
      rescue URI::Error, Addressable::URI::InvalidURIError, ArgumentError
        ""
      end
    end

    get("/harness/urlhelper-cook-url") do
      UrlHelper.cook_url(
        params["url"].to_s,
        secure: truthy?(params["secure"]),
        local: parse_optional_bool(params["local"]),
      ).to_s
    end

    get("/harness/search-ts-config") do
      Search.ts_config(params["locale"].presence || SiteSetting.default_locale).to_s
    end

    get("/harness/search-clean-term") do
      Search.clean_term(params["term"].to_s).to_s
    end

    get("/harness/search-word-to-date") do
      Search.word_to_date(params["str"].to_s)&.to_s || ""
    end

    get("/harness/search-prepare-data") do
      purpose =
        case params["purpose"].to_s
        when "", "nil", "null"
          nil
        when "topic", ":topic"
          :topic
        else
          params["purpose"].to_s
        end
      Search.prepare_data(params["search_data"].to_s, purpose).to_s
    end

    get("/harness/filehelper-download") do
      tmp =
        FileHelper.download(
          params["url"].to_s,
          max_file_size: (params["max_file_size"] || "1048576").to_i,
          tmp_file_name: (params["tmp_file_name"].presence || "harness"),
          follow_redirect: truthy?(params["follow_redirect"]),
          read_timeout: (params["read_timeout"] || "5").to_i,
          skip_rate_limit: truthy?(params["skip_rate_limit"]),
          verbose: truthy?(params["verbose"]),
          validate_uri: !falsy?(params["validate_uri"]),
          retain_on_max_file_size_exceeded: truthy?(params["retain_on_max_file_size_exceeded"]),
          include_port_in_host_header: truthy?(params["include_port_in_host_header"]),
          extra_headers: {},
        )
      if tmp
        body = tmp.read.to_s
        tmp.close!
        body
      else
        ""
      end
    end

    get("/harness/finaldestination-resolve") do
      FinalDestination.resolve(params["url"].to_s).to_s
    end

    get("/harness/finaldestination-is-https-domain-") do
      FinalDestination.is_https_domain?(params["domain"].to_s).to_s
    end

    post("/harness/prettytext-lookup-mentions") do
      PrettyText.send(
        :lookup_mentions,
        parse_names_param(params["names"]),
        user_id: params["user_id"].to_i,
      ).to_json
    end

    post("/harness/prettytext-add-rel-attributes-to-user-content") do
      doc = Nokogiri::HTML5.fragment(params["doc"].to_s)
      PrettyText.add_rel_attributes_to_user_content(doc, truthy?(params["add_nofollow"]))
      doc.to_html
    end

    not_found do
      content_type "text/plain"
      "not found"
    end

    error do
      content_type "text/plain"
      "#{env["sinatra.error"].class}: #{env["sinatra.error"].message}"
    end
  end

  App.run!
else
  Rack::Handler::WEBrick.run(
    app,
    Host: "0.0.0.0",
    Port: port,
    AccessLog: [],
    Logger: Logger.new($stdout),
  )
end
