# frozen_string_literal: true

require "sinatra/base"
require "json"
require "set"
require "date"
require "time"

$LOAD_PATH.unshift(File.join(__dir__, "lib"))

# Minimal DB-only boot for Tier 2 targets
begin
  require "active_record"
  require "active_support/all"

  db_name = ENV["DB_NAME"] || ENV["DISCOURSE_DEV_DB"] || "discourse_development"
  db_user = ENV["DB_USER"] || "postgres"
  db_host = ENV["PGHOST"] || ENV["DB_HOST"] || ENV["DATABASE_HOST"] || "localhost"

  ActiveRecord::Base.establish_connection(
    adapter: "postgresql",
    host: db_host,
    database: db_name,
    username: db_user,
    password: ENV["PGPASSWORD"],
  )
rescue => e
  warn "[harness] ActiveRecord init failed: #{e.class}: #{e.message}"
end

class HarnessApp < Sinatra::Base
  set :port, (ENV["PORT"] || 3001).to_i
  set :bind, "0.0.0.0"

  before do
    content_type "text/plain"
  end

  get "/health" do
    "ok"
  end

  LOADED_TARGETS = {}

  def self.safe_require(key, *paths)
    begin
      paths.each { |path| require_relative path }
      LOADED_TARGETS[key] = true
    rescue LoadError, StandardError => e
      LOADED_TARGETS[key] = false
      warn "[harness] skipped #{key}: #{e.class}: #{e.message}"
    end
  end

  safe_require(:user_search, "app/models/user_search")
  safe_require(:search_log, "app/models/search_log")
  safe_require(:tags_search, "app/services/tags/search")
  safe_require(:category_hierarchical_search, "app/services/category/hierarchical_search")

  helpers do
    def json_params
      request.media_type == "application/json" ? JSON.parse(request.body.read) : {}
    rescue
      {}
    end

    def param_value(name)
      params[name.to_s] || json_params[name.to_s] || json_params[name.to_sym]
    end

    def parse_int(name)
      v = param_value(name)
      v.nil? || v == "" ? nil : v.to_i
    end

    def parse_bool(name)
      v = param_value(name)
      return false if v.nil?
      return v if v == true || v == false
      %w[true 1 yes on].include?(v.to_s.downcase)
    end

    def parse_array(name)
      v = param_value(name)
      return [] if v.nil?
      return v if v.is_a?(Array)
      JSON.parse(v)
    rescue
      [v]
    end

    def call_and_render
      result = yield
      result.is_a?(String) ? result : result.to_json
    end
  end

  get "/harness/search_ids" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:user_search]
    begin
      term = param_value(:term).to_s
      topic_id = parse_int(:topic_id)
      category_id = parse_int(:category_id)
      limit = parse_int(:limit) || 20
      call_and_render { UserSearch.new(term, topic_id: topic_id, category_id: category_id, limit: limit).search_ids }
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/search" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:user_search]
    begin
      term = param_value(:term).to_s
      topic_id = parse_int(:topic_id)
      category_id = parse_int(:category_id)
      call_and_render { UserSearch.new(term, topic_id: topic_id, category_id: category_id).search }
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/filtered_by_term_users" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:user_search]
    begin
      term = param_value(:term).to_s
      include_staged_users = parse_bool(:include_staged_users)
      call_and_render { UserSearch.new(term, include_staged_users: include_staged_users).filtered_by_term_users }
    rescue => e
      status 500
      e.message
    end
  end

  post "/harness/log" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:search_log]
    begin
      term = param_value(:term).to_s
      search_type = param_value(:search_type).to_s.to_sym
      ip_address = param_value(:ip_address).to_s
      user_agent = param_value(:user_agent).to_s
      user_id = parse_int(:user_id)
      call_and_render do
        SearchLog.log(
          term: term,
          search_type: search_type,
          ip_address: ip_address,
          user_agent: user_agent,
          user_id: user_id,
        )
      end
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/term_details" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:search_log]
    begin
      term = param_value(:term).to_s
      period = (param_value(:period) || "weekly").to_s.to_sym
      search_type = (param_value(:search_type) || "all").to_s.to_sym
      call_and_render { SearchLog.term_details(term, period, search_type) }
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/trending_from" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:search_log]
    begin
      start_date = param_value(:start_date)
      search_type = (param_value(:search_type) || "all").to_s.to_sym
      limit = parse_int(:limit) || 100
      start_date = Date.parse(start_date.to_s) rescue Time.parse(start_date.to_s) rescue start_date
      call_and_render { SearchLog.trending_from(start_date, search_type: search_type, limit: limit) }
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/trending" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:search_log]
    begin
      period = (param_value(:period) || "weekly").to_s.to_sym
      search_type = (param_value(:search_type) || "all").to_s.to_sym
      call_and_render { SearchLog.trending(period, search_type) }
    rescue => e
      status 500
      e.message
    end
  end

  post "/harness/clean_up" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:search_log]
    begin
      call_and_render { SearchLog.clean_up }
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/search_tags" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:tags_search]
    begin
      q = param_value(:q).to_s
      limit = parse_int(:limit)
      category_id = parse_int(:categoryId)
      call_and_render { Tags::Search.call(guardian: nil, params: { q: q, limit: limit, categoryId: category_id }) }
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/append_disabled_tags" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:tags_search]
    begin
      q = param_value(:q).to_s
      selected_tag_ids = parse_array(:selected_tag_ids)
      filter_for_input = parse_bool(:filterForInput)
      call_and_render do
        Tags::Search.new.call(
          guardian: nil,
          params: { q: q, selected_tag_ids: selected_tag_ids, filterForInput: filter_for_input },
        )
      end
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/detect_forbidden_tag" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:tags_search]
    begin
      q = param_value(:q).to_s
      selected_tag_ids = parse_array(:selected_tag_ids)
      filter_for_input = parse_bool(:filterForInput)
      call_and_render do
        Tags::Search.new.call(
          guardian: nil,
          params: { q: q, selected_tag_ids: selected_tag_ids, filterForInput: filter_for_input },
        )
      end
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/explain_exclusion" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:tags_search]
    begin
      tag = JSON.parse(param_value(:tag).to_s) rescue {}
      selected_ids = parse_array(:selected_ids)
      filter_for_input = parse_bool(:filterForInput)
      call_and_render do
        Tags::Search.new.call(
          guardian: nil,
          params: { tag: tag, selected_ids: selected_ids, filterForInput: filter_for_input },
        )
      end
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/fetch_categories" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:category_hierarchical_search]
    begin
      term = param_value(:term).to_s
      only = parse_array(:only)
      except = parse_array(:except)
      page = parse_int(:page) || 1
      call_and_render do
        Category::HierarchicalSearch.new.call(
          guardian: nil,
          params: { term: term, only: only, except: except, page: page },
        )
      end
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/eager_load_associations" do
    halt 404, "target not loaded" unless LOADED_TARGETS[:category_hierarchical_search]
    begin
      categories = parse_array(:categories)
      call_and_render do
        Category::HierarchicalSearch.new.call(
          guardian: nil,
          params: { categories: categories },
        )
      end
    rescue => e
      status 500
      e.message
    end
  end
end

HarnessApp.run! if $PROGRAM_NAME == __FILE__
