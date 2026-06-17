#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "logger"
require "uri"
require "tempfile"
require "ostruct"
require "cgi"
require "set"
require "time"
require "date"
require "net/http"
require "openssl"
require "nokogiri"
require "addressable/uri"
require "addressable/idna"
require "socket"
require "ipaddr"

APP_ROOT = File.expand_path(__dir__)
LIB_ROOT = File.join(APP_ROOT, "lib")

$LOAD_PATH.unshift(LIB_ROOT) unless $LOAD_PATH.include?(LIB_ROOT)
$LOAD_PATH.unshift(APP_ROOT) unless $LOAD_PATH.include?(APP_ROOT)

# Avoid Sinatra/rackup/puma dependency boot issues in the harness container.
begin
  require "sinatra/base"
rescue LoadError
  require "webrick"

  class MiniSinatraBase
    class << self
      def inherited(subclass)
        subclass.instance_variable_set(:@routes, Hash.new { |h, k| h[k] = {} })
        subclass.instance_variable_set(:@error_handler, nil)
        super
      end

      def configure(&blk)
        instance_eval(&blk) if blk
      end

      def set(_key, _value); end

      def before(&blk)
        @before_filter = blk
      end

      def error(&blk)
        @error_handler = blk
      end

      def get(path, &blk)
        @routes["GET"][path] = blk
      end

      def post(path, &blk)
        @routes["POST"][path] = blk
      end

      def routes
        @routes
      end

      def before_filter
        @before_filter
      end

      def error_handler
        @error_handler
      end

      def run!
        port = (ENV["PORT"] || 3001).to_i
        server = WEBrick::HTTPServer.new(
          Port: port,
          BindAddress: "0.0.0.0",
          AccessLog: [],
          Logger: Logger.new($stderr, level: Logger::ERROR),
        )

        trap("INT") { server.shutdown }
        trap("TERM") { server.shutdown }

        server.mount_proc("/") do |req, res|
          klass = self
          app = klass.new
          app.__dispatch(req, res)
        end

        server.start
      end
    end

    def __dispatch(req, res)
      @__req = req
      @__res = res
      @__status = 200
      @__headers = { "Content-Type" => "text/plain" }

      route = self.class.routes[req.request_method][req.path]

      begin
        instance_eval(&self.class.before_filter) if self.class.before_filter
        if route
          body = instance_exec(&route)
          res.status = @__status
          @__headers.each { |k, v| res[k] = v }
          res.body = body.to_s
        else
          res.status = 404
          res["Content-Type"] = "text/plain"
          res.body = "Not Found\n"
        end
      rescue => e
        if self.class.error_handler
          @__env = { "sinatra.error" => e }
          body = instance_exec(&self.class.error_handler)
          res.status = @__status
          @__headers.each { |k, v| res[k] = v }
          res.body = body.to_s
        else
          res.status = 500
          res["Content-Type"] = "text/plain"
          res.body = "#{e.class}: #{e.message}\n"
        end
      end
    end

    def env
      @__env || {}
    end

    def params
      @params ||= begin
        h = {}
        @__req.query.each { |k, v| h[k] = v }
        if @__req.request_method == "POST" && @__req.content_type.to_s.include?("application/json")
          begin
            parsed = JSON.parse(@__req.body.to_s)
            parsed.each { |k, v| h[k.to_s] = v } if parsed.is_a?(Hash)
          rescue
          end
        end
        h
      end
    end

    def content_type(v)
      @__headers["Content-Type"] = v
    end

    def status(v = nil)
      @__status = v if v
      @__status
    end
  end

  module Sinatra
    Base = MiniSinatraBase
  end
end

def safe_require(path, label)
  absolute =
    if path.end_with?(".rb")
      File.expand_path(path, APP_ROOT)
    else
      File.expand_path("#{path}.rb", APP_ROOT)
    end

  begin
    require absolute
    warn("[harness] loaded #{label}") if ENV["HARNESS_DEBUG"]
    true
  rescue LoadError, StandardError => e
    warn("[harness] skip #{label}: #{e.class}: #{e.message}")
    false
  end
end

class Numeric
  def second = self
  def seconds = self
  def minute = self * 60
  def minutes = self * 60
  def hour = self * 3600
  def hours = self * 3600
  def day = self * 86_400
  def days = self * 86_400
  def week = self * 604_800
  def weeks = self * 604_800

  def ago
    Time.now - self
  end
end

class String
  def present? = !empty?
  def blank? = empty?
  def presence = present? ? self : nil
  def starts_with?(*prefixes) = prefixes.any? { |p| start_with?(p) }
  def ends_with?(*suffixes) = suffixes.any? { |s| end_with?(s) }
  def truncate(max)
    return self if length <= max
    self[0, max]
  end
  def squish
    dup.squish!
  end
  def squish!
    gsub!(/\s+/, " ")
    strip!
    self
  end
  def titlecase
    split(/\s+/).map(&:capitalize).join(" ")
  end
  def with_indifferent_access
    self
  end
end

class NilClass
  def present? = false
  def blank? = true
  def presence = nil
end

class Object
  def present? = !blank?
  def blank? = false
  def presence = present? ? self : nil
  def try(*args, &blk)
    if args.empty? && block_given?
      yield self
    elsif respond_to?(args.first)
      public_send(*args, &blk)
    end
  end
end

class Array
  def present? = !empty?
  def blank? = empty?
  def presence = present? ? self : nil
  def with_indifferent_access = self

  def self.wrap(obj)
    return [] if obj.nil?
    obj.is_a?(Array) ? obj : [obj]
  end
end

class Hash
  def present? = !empty?
  def blank? = empty?
  def presence = present? ? self : nil

  def with_indifferent_access
    indifferent = {}
    each do |k, v|
      indifferent[k.to_s] = v
      indifferent[k.to_sym] = v rescue nil
    end
    indifferent
  end

  def except(*keys)
    dup.reject { |k, _| keys.include?(k) || keys.include?(k.to_s) || keys.include?(k.to_sym) }
  end

  def reverse_merge(other)
    other.merge(self)
  end

  def reverse_merge!(other)
    replace(other.merge(self))
  end

  def assert_valid_keys(*valid_keys)
    valid_keys.flatten!
    each_key do |k|
      raise ArgumentError, "Unknown key: #{k}" unless valid_keys.include?(k)
    end
  end
end

module Kernel
  def cattr_accessor(*names)
    names.each do |name|
      singleton_class.class_eval { attr_accessor name }
      define_singleton_method(name) { instance_variable_get("@#{name}") }
      define_singleton_method("#{name}=") { |v| instance_variable_set("@#{name}", v) }
    end
  end
end

class Module
  def profile(*)
    self
  end

  def profile?(*)
    false
  end
end

class Class
  def profile(*)
    self
  end

  def profile?(*)
    false
  end
end

module Discourse
  class InvalidParameters < StandardError
    attr_reader :param
    def initialize(param)
      @param = param
      super("invalid parameters: #{param}")
    end
  end

  class InvalidAccess < StandardError; end

  def self.base_url
    ENV["HARNESS_BASE_URL"] || "http://127.0.0.1:3001"
  end

  def self.base_url_no_prefix
    base_url
  end

  def self.base_path
    ""
  end

  def self.asset_host
    nil
  end

  def self.readonly_mode?
    false
  end

  def self.route_for(_url)
    nil
  end

  def self.plugins
    []
  end

  def self.store
    @store ||= Struct.new(:upload_path) do
      def has_been_uploaded?(_url) = false
      def external? = false
      def cdn_url(url) = url
      def absolute_base_url = "http://127.0.0.1:3001"
    end.new("uploads")
  end

  def self.redis
    @redis ||= begin
      backing = {}
      mod = Module.new
      mod.define_singleton_method(:without_namespace) { mod }
      mod.define_singleton_method(:get) { |k| backing[k] }
      mod.define_singleton_method(:setex) { |k, _ttl, v| backing[k] = v }
      mod.define_singleton_method(:del) { |k| backing.delete(k) }
      mod.define_singleton_method(:write) { |k, v, **_| backing[k] = v }
      mod.define_singleton_method(:read) { |k| backing[k] }
      mod.define_singleton_method(:fetch) { |k, **_| backing[k] }
      mod
    end
  end

  def self.cache
    @cache ||= begin
      backing = {}
      mod = Module.new
      mod.define_singleton_method(:read) { |k| backing[k] }
      mod.define_singleton_method(:write) { |k, v, **_| backing[k] = v }
      mod.define_singleton_method(:delete) { |k| backing.delete(k) }
      mod.define_singleton_method(:fetch) do |k, **_|
        return backing[k] if backing.key?(k)
        backing[k] = yield
      end
      mod
    end
  end
end

module RailsMultisite
  module ConnectionManagement
    def self.current_db = "default"
  end
end

module Rails
  def self.logger
    @logger ||= Logger.new($stdout)
  end

  def self.root
    APP_ROOT
  end

  def self.env
    @env ||= Struct.new(:test?).new(true)
  end

  def self.configuration
    @configuration ||= OpenStruct.new(action_controller: OpenStruct.new(asset_host: nil))
  end

  def self.application
    @application ||= OpenStruct.new(routes: OpenStruct.new(recognize_path: {}))
  end
end

module SiteSetting
  module Upload
    def self.enable_s3_uploads = false
    def self.s3_cdn_url = nil
  end

  class << self
    def method_missing(name, *args)
      n = name.to_s
      return false if n.end_with?("?")
      return "" if n.end_with?("_url") || n.end_with?("_endpoint")
      return "en" if n == "default_locale" || n == "onebox_locale"
      return "{}" if n == "client_settings_json"
      return "[]" if n == "avatar_sizes"
      return "" if n == "allowed_internal_hosts"
      return "" if n == "shared_drafts_category"
      return "0" if n == "uncategorized_category_id"
      return 10 if n =~ /(size|count|limit|page|age|offset|time|days|hours|minutes|seconds|length|ttl|timeout|results)\z/
      nil
    end

    def respond_to_missing?(*_) = true
  end
end

module GlobalSetting
  def self.hostname = "127.0.0.1"
  def self.s3_cdn_url = nil
  def self.cdn_url = nil
  def self.mini_racer_single_threaded = true
end

module I18n
  def self.t(key, **opts)
    return key.to_s if opts.empty?
    "#{key}: #{opts.map { |k, v| "#{k}=#{v}" }.join(", ")}"
  end
end

module Emoji
  def self.gsub_emoji_to_unicode(s) = s.to_s
  def self.unicode_replacements_json = "{}"
  def self.custom = []
  def self.denied = []
end

module WordWatcher
  def self.censor_text(s) = s
  def self.censor(s) = s
  def self.serialized_regexps_for_action(_a) = []
  def self.regexps_for_action(_a) = []
end

module Onebox
  module Helpers
    def self.user_agent = "BrightHarness/1.0"
    def self.normalize_url_for_output(url) = url.to_s
    def self.sanitize(s) = s.to_s
  end

  class DomainChecker
    def self.is_blocked?(_host) = false
  end

  class Matcher
    def initialize(url, *_args) = @url = url
    def oneboxed = nil
  end

  module SanitizeConfig
    DISCOURSE_ONEBOX = {}
  end

  module Engine
    def self.origins_to_regexes(origins) = Array.wrap(origins)
    def self.all_iframe_origins = []
  end

  def self.preview(_url, _opts = {})
    OpenStruct.new(
      to_s: "",
      placeholder_html: "",
      errors: {},
      verified_data: {},
    )
  end
end

module SSRFDetector
  class DisallowedIpError < StandardError; end
  def self.lookup_and_filter_ips(hostname)
    [hostname]
  end
end

module Excon
  def self.defaults
    @defaults ||= { middlewares: [] }
  end

  module Middleware
    class Decompress; end
  end

  class Response
    attr_accessor :status, :headers, :data
    def initialize(status: 200, headers: {}, data: {})
      @status = status
      @headers = headers
      @data = data
    end
  end

  module Errors
    class Timeout < StandardError; end
    class ExpectationFailed < StandardError; end
  end

  def self.head(_url, **_)
    Response.new(status: 200, headers: {})
  end

  def self.get(_url, **_)
    Response.new(status: 200, headers: {})
  end
end

module MiniMime
  Entry = Struct.new(:extension)
  def self.lookup_by_content_type(content_type)
    case content_type.to_s
    when /html/i then Entry.new("html")
    when /json/i then Entry.new("json")
    when /jpeg/i then Entry.new("jpg")
    when /png/i then Entry.new("png")
    else nil
    end
  end
end

module Loofah
  def self.html5_fragment(html)
    Nokogiri::HTML5.fragment(html.to_s)
  end

  class Scrubber
    def initialize(&blk)
      @blk = blk
    end

    def call(node)
      @blk.call(node)
    end
  end
end

module DiscourseEvent
  def self.trigger(*_) = nil
end

module DB
  def self.query(*_)
    []
  end

  def self.query_single(*_)
    [nil]
  end

  def self.sql_fragment(sql, *_args)
    sql
  end
end

module ActiveRecord
  class StatementInvalid < StandardError; end
  class Base
    def self.connection
      OpenStruct.new(quote: ->(v) { "'#{v}'" })
    end
  end
end

module ActiveModel
  module Type
    class Boolean
      def cast(v)
        [true, "true", 1, "1"].include?(v)
      end
    end
  end
end

module Searchable
  PRIORITIES = { very_high: 3, high: 2, low: 1, very_low: 0, ignore: -1 }
end

module SearchSortOrderSiteSetting
  def self.value_from_id(v) = v
  def self.id_from_value(v) = v
end

module TopicPostersSummary
  def self.translations = {}
end

class UserLookup
  def initialize(*); end
end

class TopicList
  attr_accessor :per_page, :filter_option_info
  def initialize(*); end
end

class TopicsFilter
  attr_reader :topic_notification_levels

  def initialize(*_, **__)
    @topic_notification_levels = []
  end

  def filter_from_query_string(_q)
    []
  end

  def self.option_info(_guardian)
    {}
  end

  def filter_status(status:, category_id:)
    []
  end
end

module NotificationLevels
  def self.all
    { muted: 0, regular: 1, tracking: 2, watching: 3 }
  end
end

class Guardian
  attr_reader :user

  def initialize(user = nil)
    @user = user
  end

  def authenticated? = !@user.nil?
  def can_lazy_load_categories? = false
  def can_see_private_messages?(_id) = false
  def can_see_unlisted_topics? = false
  def can_see_whispers? = false
  def is_admin? = false
  def can_see?(_obj) = true
  def can_see_topic?(_topic) = true
  def can_see_category?(_category) = true
  def can_see_post?(_post) = true
  def can_see_shared_draft? = false
  def can_see_tag?(_tag) = true
  def allowed_category_ids = []
  def secure_category_ids = []
  def filter_allowed_categories(scope, **_) = scope
end

class GroupedSearchResults
  BLURB_LENGTH = 200
  attr_accessor :search_log_id
  attr_reader :posts, :type_filter

  def initialize(type_filter:, **_)
    @type_filter = type_filter || "all_topics"
    @posts = []
  end

  def add(obj)
    @posts << obj
  end
end

class SearchLog
  def self.log(**_)
    [:ok, 1]
  end
end

class TagsController
  def self.tag_counts_json(tags, _guardian)
    Array.wrap(tags).map do |t|
      if t.is_a?(Hash)
        t
      else
        {
          id: t.respond_to?(:id) ? t.id : nil,
          name: t.respond_to?(:name) ? t.name : t.to_s,
          text: t.respond_to?(:name) ? t.name : t.to_s,
          count: 0,
        }
      end
    end
  end
end

module DiscourseTagging
  def self.clean_tag(s) = s.to_s.strip
  def self.hidden_tag_names(_guardian) = []
  def self.visible_tags(_guardian) = []
  def self.filter_visible(scope, _guardian) = scope
  def self.filter_allowed_tags(_guardian, **_)
    [[], { required_tag_group: nil }]
  end
end

module Service
  module Base
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def params(&blk)
        klass = Class.new do
          class << self
            attr_accessor :_attrs
          end
          self._attrs = []

          def self.attribute(name, _type)
            self._attrs << name
            attr_accessor name
          end

          def self.validate(*); end

          def initialize(attrs = {})
            @raw_attributes = attrs || {}
            self.class._attrs.each do |name|
              send("#{name}=", attrs[name.to_s] || attrs[name.to_sym]) if respond_to?("#{name}=")
            end
          end

          def raw_attributes
            @raw_attributes || {}
          end

          def errors
            @errors ||= Class.new do
              def add(*); end
            end.new
          end
        end

        klass.class_eval(&blk)
        define_singleton_method(:params_class) { klass }
      end

      def model(_name, optional: false)
        define_singleton_method(:_model_optional) { optional }
      end

      def step(name)
        (@_steps ||= []) << name
      end

      def only_if(_name, &blk)
        (@_conditional_steps ||= []) << blk
      end

      def call(**kwargs)
        service = new
        service.instance_variable_set(:@context, {})
        params_obj = respond_to?(:params_class) ? params_class.new(kwargs[:params] || {}) : nil
        category = service.respond_to?(:fetch_category, true) ? service.send(:fetch_category, params: params_obj) : nil

        if service.respond_to?(:search_tags, true)
          service.send(:search_tags, params: params_obj, category: category, guardian: kwargs[:guardian])
        end

        if service.respond_to?(:has_term_for_input, true) && service.send(:has_term_for_input, params: params_obj)
          service.send(:append_disabled_tags, params: params_obj, tags: service.context[:tags] || [], guardian: kwargs[:guardian]) if service.respond_to?(:append_disabled_tags, true)
        end

        if service.respond_to?(:has_term, true) && service.send(:has_term, params: params_obj)
          service.send(:detect_forbidden_tag, params: params_obj, tags: service.context[:tags] || [], guardian: kwargs[:guardian]) if service.respond_to?(:detect_forbidden_tag, true)
        end

        service.context
      end
    end

    def context
      @context ||= {}
    end
  end
end

class TagRelation < Array
  def where(*_) = self
  def where_name(*_) = self
  def joins(*_) = self
  def includes(*_) = self
  def preload(*_) = self
  def references(*_) = self
  def order(*_) = self
  def limit(*_) = self
  def not(*_) = self
  def select(*_) = self
  def distinct = self
  def pluck(*_) = []
  def pick(*_) = nil
  def first = super
  def exists? = !empty?
  def with_localizations(v = self) = v
end

class Tag
  attr_accessor :id, :name, :target_tag_id

  def initialize(id = nil, name = nil)
    @id = id
    @name = name
  end

  def self.where(*_) = TagRelation.new
  def self.where_name(*_) = TagRelation.new
  def self.with_localizations(v) = v
  def synonym? = false
  def target_tag = nil
  def synonyms = TagRelation.new
  def categories = TagRelation.new
end

class TagGroup
  def self.joins(*_) = TagRelation.new
  def self.find_id_by_slug(*) = nil
  attr_accessor :name, :parent_tag_id
  def parent_tag = nil
end

class TagGroupMembership
  def self.where(*_) = TagRelation.new
end

class Category
  def self.find_by(*) = nil
  def self.where(*_) = TagRelation.new
  def self.joins(*_) = TagRelation.new
  def self.find_by_slug_path_with_id(*) = nil
  def self.subcategory_ids(id) = [id]
  def self.topic_ids = []
  def self.normalize_sql(v) = v
end

class User
  def self.find_by(*) = nil
  def self.find_by_username(*) = nil
  def self.where(*_) = TagRelation.new
  def self.not_staged = TagRelation.new
  def self.normalize_username(v) = v.to_s.downcase
end

class Post
  def self.types
    { regular: 1, moderator_action: 2, whisper: 3 }
  end
end

class Topic
  def self.visible_post_types(_user) = [Post.types[:regular]]
  def self.find_by(*) = nil
end

class Upload
  def self.where(*_) = TagRelation.new
  def self.base62_sha1(v) = v
  def self.secure_uploads_url?(*) = false
  def self.secure_uploads_url_from_upload_url(url) = url
end

class CategoryBadge
  def self.html_for(*) = ""
end

class UserSerializer
  def initialize(*); end
  def website_name = nil
end

class Archetype
  def self.default = "regular"
  def self.private_message = "private_message"
end

class TopicUser
  def self.notification_levels
    { muted: 0, regular: 1, tracking: 2, watching: 3 }
  end
end

class CategoryUser
  def self.notification_levels
    { muted: 0, watching_first_post: 1, watching: 2 }
  end
  def self.default_notification_level = 1
  def self.indirectly_muted_category_ids(_user) = []
end

class TagUser
  def self.notification_levels
    { watching_first_post: 1 }
  end
  def self.lookup(*_) = TagRelation.new
end

class PostActionType
  def self.types
    { like: 2 }
  end
end

class TopicTag
  def self.select(*) = TagRelation.new
  def self.distinct = self
  def self.where(*) = TagRelation.new
  def self.to_sql = "SELECT 1"
end

class RandomTopicSelector
  def self.next(*_) = []
end

class SharedDraft
  def self.where(*) = TagRelation.new
end

module PrivateMessageLists
end

class Mustache
  def self.render(_template, _args = {})
    ""
  end
end

module FinalDestination
  HTTP = Net::HTTP unless const_defined?(:HTTP)
  class SSRFError < SocketError; end unless const_defined?(:SSRFError)
  class UrlEncodingError < ArgumentError; end unless const_defined?(:UrlEncodingError)
end

module Tags
end

module RateLimiter
end

safe_require("lib/url_helper", "UrlHelper")
safe_require("lib/final_destination", "FinalDestination")
safe_require("lib/file_helper", "FileHelper")
safe_require("lib/retrieve_title", "RetrieveTitle")
safe_require("lib/inline_oneboxer", "InlineOneboxer")

# Oneboxer eagerly requires all engine files, which in turn pull optional gems
# such as `htmlentities`. For the harness, only the exposed API surface is needed,
# so fall back to a small compatible implementation if the full file can't load.
unless safe_require("lib/oneboxer", "Oneboxer")
  module Oneboxer
    def self.onebox_locale
      SiteSetting.onebox_locale.presence || SiteSetting.default_locale
    end

    def self.accept_language
      if onebox_locale == "en"
        "en;q=0.9, *;q=0.5"
      else
        "#{onebox_locale.gsub(/_/, "-")};q=0.9, en;q=0.8, *;q=0.5"
      end
    end

    def self.local_topic(_url, _route, _opts)
      nil
    end

    def self.onebox(url, options = nil)
      options ||= {}
      preview(url, options)[:onebox]
    end

    def self.preview(url, _options = nil)
      { preview: "", onebox: "<a href='#{CGI.escapeHTML(url.to_s)}'>#{CGI.escapeHTML(url.to_s)}</a>" }
    end
  end
end

unless safe_require("lib/pretty_text", "PrettyText")
  module PrettyText
    def self.cook(raw, _opts = {})
      raw.to_s
    end

    def self.format_for_email(html, _post = nil)
      doc = Nokogiri::HTML5.fragment(html.to_s)
      doc.css("script").remove
      doc.to_html
    end

    def self.avatar_img(*)
      ""
    end

    def self.unescape_emoji(s)
      s.to_s
    end
  end
end

unless safe_require("lib/search", "Search")
  class Search
    def self.execute(term, opts = nil)
      { term: term, opts: opts, error: "search unavailable in harness" }
    end
  end
end

unless safe_require("lib/topic_query", "TopicQuery")
  class TopicQuery
    def initialize(user = nil, options = {})
      @user = user
      @options = options
    end

    def list_latest
      { user: @user, options: @options, error: "topic query unavailable in harness" }
    end
  end
end

unless safe_require("app/services/tags/search", "Tags::Search")
  module Tags
    class Search
      def self.call(guardian:, params:)
        { guardian: guardian.class.name, params: params, error: "tags search unavailable in harness" }
      end
    end
  end
end

class HarnessApp < Sinatra::Base
  configure do
    set :bind, "0.0.0.0"
    set :port, (ENV["PORT"] || 3001).to_i
    set :show_exceptions, false
    set :raise_errors, true
  end

  before do
    content_type "text/plain"
  end

  get("/health") { "ok\n" }

  error do
    e = env["sinatra.error"]
    status 500
    "#{e.class}: #{e.message}\n"
  end

  post("/harness/filehelper-download") do
    begin
      result = FileHelper.download(
        params["url"],
        max_file_size: params["max_file_size"].to_i,
        tmp_file_name: params["tmp_file_name"].to_s,
        follow_redirect: params["follow_redirect"] == "true",
      )
      if result
        body = result.read
        result.close rescue nil
        result.unlink rescue nil
        body.to_s
      else
        "nil\n"
      end
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/finaldestination-get") do
    begin
      headers_hash =
        if params["headers"].to_s.strip.empty?
          {}
        else
          JSON.parse(params["headers"])
        end

      fd = FinalDestination.new(
        params["url"],
        max_redirects: params["max_redirects"].to_i,
        headers: headers_hash,
      )

      out = []
      res = fd.get do |response, chunk, uri|
        out << "status=#{response&.code} uri=#{uri}\n"
        out << chunk.to_s if chunk
      end
      out << "result=#{res.inspect}\n"
      out << "fd_status=#{fd.status.inspect}\n"
      out.join
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/retrievetitle-crawl") do
    begin
      headers_hash =
        if params["headers"].to_s.strip.empty?
          {}
        else
          JSON.parse(params["headers"])
        end
      title = RetrieveTitle.crawl(
        params["url"],
        max_redirects: params["max_redirects"].to_i,
        headers: headers_hash,
      )
      "#{title.inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/inlineoneboxer-lookup") do
    begin
      opts = params["opts"].to_s.strip.empty? ? {} : JSON.parse(params["opts"])
      "#{InlineOneboxer.lookup(params["url"], opts).inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/oneboxer-onebox") do
    begin
      options = params["options"].to_s.strip.empty? ? {} : JSON.parse(params["options"])
      "#{Oneboxer.onebox(params["url"], options).inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/retrievetitle-extract-title") do
    begin
      "#{RetrieveTitle.extract_title(params["html"], params["encoding"]).inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  post("/harness/prettytext-cook") do
    begin
      opts = params["opts"].to_s.strip.empty? ? {} : JSON.parse(params["opts"])
      "#{PrettyText.cook(params["raw"], opts).to_s}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/prettytext-format-for-email") do
    begin
      post_obj = nil
      if params["post"].to_s.strip != "" && params["post"] != "null"
        raw_post = JSON.parse(params["post"])
        post_obj =
          if raw_post.is_a?(Hash)
            OpenStruct.new(raw_post)
          else
            raw_post
          end
      end
      "#{PrettyText.format_for_email(params["html"], post_obj).to_s}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/urlhelper-normalized-encode") do
    begin
      "#{UrlHelper.normalized_encode(params["uri"]).to_s}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/search-execute") do
    begin
      opts = params["opts"].to_s.strip.empty? ? {} : JSON.parse(params["opts"])
      result = Search.execute(params["term"], opts)
      "#{result.inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/tags--search-call") do
    begin
      params_hash = params["params"].to_s.strip.empty? ? {} : JSON.parse(params["params"])
      guardian = Guardian.new
      result = Tags::Search.call(guardian: guardian, params: params_hash)
      "#{result.inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end

  get("/harness/topicquery-list-latest") do
    begin
      options = params["options"].to_s.strip.empty? ? {} : JSON.parse(params["options"])
      user = nil
      tq = TopicQuery.new(user, options)
      "#{tq.list_latest.inspect}\n"
    rescue => e
      status 500
      "#{e.class}: #{e.message}\n"
    end
  end
end

HarnessApp.run!
