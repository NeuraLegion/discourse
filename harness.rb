# frozen_string_literal: true

require "sinatra/base"
require "json"
require "uri"
require "addressable/uri"
require "ostruct"
require "set"

$LOAD_PATH.unshift(File.join(__dir__, "lib"))
$LOAD_PATH.unshift(File.join(__dir__, "app", "services"))

begin
  require "active_support/all"
rescue LoadError => e
  warn "[harness] warning: active_support/all unavailable: #{e.message}"
end

LOADED_TARGETS = {}

def load_target(key, path)
  require_relative path
  LOADED_TARGETS[key] = true
rescue LoadError => e
  warn "[harness] warning: skipped #{path} (LoadError: #{e.message})"
  LOADED_TARGETS[key] = false
rescue StandardError => e
  warn "[harness] warning: skipped #{path} (#{e.class}: #{e.message})"
  LOADED_TARGETS[key] = false
end

load_target(:search, "lib/search")
load_target(:url_helper, "lib/url_helper")
load_target(:final_destination, "lib/final_destination")
load_target(:tags_search, "app/services/tags/search")
load_target(:category_hierarchical_search, "app/services/category/hierarchical_search")
load_target(:admin_search_list, "app/services/admin/search/list")

class HarnessApp < Sinatra::Base
  configure do
    set :bind, "0.0.0.0"
    set :port, Integer(ENV.fetch("PORT", "3001"))
    set :show_exceptions, false
  end

  before do
    content_type "text/plain"
  end

  error do
    e = env["sinatra.error"]
    status 500
    "#{e.class}: #{e.message}"
  end

  get "/health" do
    "ok"
  end

  def call_target
    yield
  rescue StandardError => e
    status 500
    "#{e.class}: #{e.message}"
  end

  get "/harness/search-prepare-data" do
    return "target not loaded" unless LOADED_TARGETS[:search]
    call_target { Search.prepare_data(params["search_data"], params["purpose"]&.to_sym).to_s }
  end

  get "/harness/search-word-to-date" do
    return "target not loaded" unless LOADED_TARGETS[:search]
    call_target { Search.word_to_date(params["str"]).inspect }
  end

  get "/harness/search-clean-term" do
    return "target not loaded" unless LOADED_TARGETS[:search]
    call_target { Search.clean_term(params["term"]).to_s }
  end

  get "/harness/urlhelper-is-valid-url-" do
    return "target not loaded" unless LOADED_TARGETS[:url_helper]
    call_target { UrlHelper.is_valid_url?(params["url"]).inspect }
  end

  get "/harness/urlhelper-relaxed-parse" do
    return "target not loaded" unless LOADED_TARGETS[:url_helper]
    call_target do
      obj = UrlHelper.relaxed_parse(params["url"])
      obj ? obj.to_s : ""
    end
  end

  get "/harness/urlhelper-normalized-encode" do
    return "target not loaded" unless LOADED_TARGETS[:url_helper]
    call_target { UrlHelper.normalized_encode(params["uri"]).to_s }
  end

  get "/harness/urlhelper-cook-url" do
    return "target not loaded" unless LOADED_TARGETS[:url_helper]
    call_target do
      secure = params["secure"].to_s == "true"
      local = case params["local"]
              when nil then nil
              when "true" then true
              when "false" then false
              else params["local"]
              end
      UrlHelper.cook_url(params["url"], secure: secure, local: local).to_s
    end
  end

  get "/harness/finaldestination-resolve" do
    return "target not loaded" unless LOADED_TARGETS[:final_destination]
    call_target do
      opts = params["opts"].to_s.strip.empty? ? {} : JSON.parse(params["opts"])
      FinalDestination.resolve(params["url"], opts).to_s
    end
  end

  get "/harness/finaldestination-get" do
    return "target not loaded" unless LOADED_TARGETS[:final_destination]
    call_target do
      redirects = params["redirects"].to_i
      extra_headers = params["extra_headers"].to_s.strip.empty? ? {} : JSON.parse(params["extra_headers"])
      except_headers = params["except_headers"].to_s.strip.empty? ? [] : JSON.parse(params["except_headers"])
      fd = FinalDestination.new(params["url"], {})
      result = nil
      fd.get(redirects, extra_headers: extra_headers, except_headers: except_headers) { |_resp, _chunk, _uri| }
      result ||= fd.instance_variable_get(:@uri)&.to_s
      result.to_s
    end
  end

  get "/harness/tags--search-search-tags" do
    return "target not loaded" unless LOADED_TARGETS[:tags_search]
    call_target do
      guardian = Object.new
      params_obj = JSON.parse(params["params"] || '{"q":"ruby"}', symbolize_names: false)
      result = Tags::Search.call(guardian: guardian, params: params_obj)
      result.to_h.to_json
    end
  end

  get "/harness/tags--search-detect-forbidden-tag" do
    return "target not loaded" unless LOADED_TARGETS[:tags_search]
    call_target do
      guardian = Object.new
      params_obj = JSON.parse(params["params"] || '{"q":"private"}')
      tags = JSON.parse(params["tags"] || "[]")
      result = Tags::Search.call(guardian: guardian, params: params_obj)
      result.to_h.to_json
    end
  end

  get "/harness/category--hierarchicalsearch-fetch-categories" do
    return "target not loaded" unless LOADED_TARGETS[:category_hierarchical_search]
    call_target do
      guardian = Object.new
      params_obj = JSON.parse(params["params"] || '{"term":"support"}')
      result = Category::HierarchicalSearch.call(guardian: guardian, params: params_obj)
      result.to_h.to_json
    end
  end

  get "/harness/admin--search--list-fetch-settings" do
    return "target not loaded" unless LOADED_TARGETS[:admin_search_list]
    call_target do
      params_obj = JSON.parse(params["params"] || '{"filter_names":["foo"]}')
      result = Admin::Search::List.call(params: params_obj)
      result.to_h.to_json
    end
  end
end

HarnessApp.run! if __FILE__ == $0
