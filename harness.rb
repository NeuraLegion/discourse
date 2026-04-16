# frozen_string_literal: true

require "sinatra/base"
require "json"
require "rack/multipart"
require_relative "config/environment"

class BrightHarness < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, 3001
  set :show_exceptions, false

  before do
    content_type "application/json"
  end

  helpers do
    def json_params
      request.POST.merge(params)
    rescue
      params
    end

    def parse_bool(v)
      v == true || v.to_s == "true" || v.to_s == "1"
    end

    def parse_object(v)
      return v if v.is_a?(Hash) || v.is_a?(Array)
      JSON.parse(v)
    rescue
      v
    end

    def upload_file_param
      return nil unless params["file"] && params["file"].respond_to?(:tempfile)

      params["file"]
    end

    def invoke_controller(klass, action_name, method_name = action_name)
      controller = klass.new
      env = Rack::MockRequest.env_for("/harness/#{action_name}")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(params)
      result = controller.send(method_name)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      [controller.response.status, body, controller.response.headers]
    end
  end

  get "/health" do
    status 200
    { ok: true }.to_json
  end

  post "/harness/create" do
    begin
      status, body, _headers = invoke_controller(UploadsController, :create)
      status status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show" do
    begin
      controller = UploadsController.new
      env = Rack::MockRequest.env_for("/harness/show")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(
        "site" => params["site"],
        "sha" => params["sha"],
        "id" => params["id"],
        "extension" => params["extension"],
      )
      controller.send(:show)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show_short" do
    begin
      controller = UploadsController.new
      env = Rack::MockRequest.env_for("/harness/show_short")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("base62" => params["base62"], "extension" => params["extension"])
      controller.send(:show_short)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show_secure" do
    begin
      controller = UploadsController.new
      env = Rack::MockRequest.env_for("/harness/show_secure")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("path" => params["path"], "extension" => params["extension"])
      controller.send(:show_secure)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/metadata" do
    begin
      controller = UploadsController.new
      env = Rack::MockRequest.env_for("/harness/metadata")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("url" => params["url"])
      controller.send(:metadata)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/search_query" do
    begin
      controller = SearchController.new
      env = Rack::MockRequest.env_for("/harness/search_query")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(
        "term" => params["term"],
        "type_filter" => params["type_filter"],
        "search_for_id" => params["search_for_id"],
        "restrict_to_archetype" => params["restrict_to_archetype"],
      )
      controller.send(:query)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/search_show" do
    begin
      controller = SearchController.new
      env = Rack::MockRequest.env_for("/harness/search_show")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("q" => params["q"], "page" => params["page"], "context" => params["context"], "context_id" => params["context_id"])
      controller.send(:show)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/search_click" do
    begin
      controller = SearchController.new
      env = Rack::MockRequest.env_for("/harness/search_click")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("search_log_id" => params["search_log_id"], "search_result_type" => params["search_result_type"], "search_result_id" => params["search_result_id"])
      controller.send(:click)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/permalink_show" do
    begin
      controller = PermalinksController.new
      env = Rack::MockRequest.env_for(params["request.fullpath"] || "/old-path")
      req = ActionDispatch::Request.new(env)
      req.env["PATH_INFO"] = params["request.fullpath"] || "/old-path"
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.send(:show)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/permalink_check" do
    begin
      controller = PermalinksController.new
      env = Rack::MockRequest.env_for("/harness/permalink_check")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("path" => params["path"])
      controller.send(:check)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/webhooks_mailgun" do
    begin
      controller = WebhooksController.new
      env = Rack::MockRequest.env_for("/harness/webhooks_mailgun", method: "POST", input: request.body.read)
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(params)
      controller.send(:mailgun)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/webhooks_sendgrid" do
    begin
      controller = WebhooksController.new
      env = Rack::MockRequest.env_for("/harness/webhooks_sendgrid", method: "POST", input: request.body.read)
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(params)
      controller.send(:sendgrid)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/webhooks_aws" do
    begin
      controller = WebhooksController.new
      env = Rack::MockRequest.env_for("/harness/webhooks_aws", method: "POST", input: params["raw_post"].to_s)
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.send(:aws)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/site_settings_index" do
    begin
      controller = Admin::SiteSettingsController.new
      env = Rack::MockRequest.env_for("/harness/site_settings_index")
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!("categories" => params["categories"], "plugin" => params["plugin"], "names" => params["names"])
      controller.send(:index)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  put "/harness/site_settings_update" do
    begin
      controller = Admin::SiteSettingsController.new
      env = Rack::MockRequest.env_for("/harness/site_settings_update", method: "PUT", input: request.body.read)
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(params)
      controller.send(:update)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  put "/harness/themes_update" do
    begin
      controller = Admin::ThemesController.new
      env = Rack::MockRequest.env_for("/harness/themes_update", method: "PUT", input: request.body.read)
      req = ActionDispatch::Request.new(env)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(params)
      controller.send(:update)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      body body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end
end

BrightHarness.run!
