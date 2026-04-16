# frozen_string_literal: true

require "sinatra/base"
require "json"
require "uri"

ENV["RACK_ENV"] ||= "development"
ENV["RAILS_ENV"] ||= "development"
ENV["SKIP_DB_AND_REDIS"] ||= "1"

require_relative "config/environment"

class HarnessServer < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, 3001

  before do
    content_type "application/json"
  end

  get "/health" do
    status 200
    { ok: true }.to_json
  end

  helpers do
    def json_params
      request.body.rewind
      body = request.body.read
      body = "{}" if body.nil? || body.empty?
      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def ensure_current_user
      if defined?(User) && User.respond_to?(:first)
        User.first || (User.respond_to?(:find_by) && User.find_by(id: 1))
      end
    end

    def invoke_controller(controller_class, action_name, http_method:, params_hash: {})
      controller = controller_class.new
      env = Rack::MockRequest.env_for(
        "/harness/#{action_name}",
        method: http_method.to_s.upcase,
        "CONTENT_TYPE" => "application/json",
      )
      req = ActionDispatch::Request.new(env)
      res = ActionDispatch::Response.new
      controller.set_request!(req)
      controller.set_response!(res)
      controller.params.merge!(ActionController::Parameters.new(params_hash))
      controller.instance_variable_set(:@_response_body, nil)
      controller.process(action_name)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      [controller.response.status, body]
    end
  end

  post "/harness/create" do
    begin
      p = json_params
      current_user = ensure_current_user
      result =
        UploadsController.create_upload(
          current_user: current_user,
          file: p["file"],
          url: p["url"],
          type: p["upload_type"] || p["type"],
          for_private_message: p["for_private_message"].to_s == "true",
          for_site_setting: p["for_site_setting"].to_s == "true",
          site_setting_name: p["site_setting_name"],
          pasted: p["pasted"].to_s == "true",
          is_api: p["is_api"].to_s == "true",
          retain_hours: p["retain_hours"].to_i,
        )
      status 200
      UploadsController.serialize_upload(result).to_json
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show" do
    begin
      status_code, body = invoke_controller(
        UploadsController,
        :show,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show_short" do
    begin
      status_code, body = invoke_controller(
        UploadsController,
        :show_short,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/_show_secure_deprecated" do
    begin
      status_code, body = invoke_controller(
        UploadsController,
        :_show_secure_deprecated,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show_secure" do
    begin
      status_code, body = invoke_controller(
        UploadsController,
        :show_secure,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/metadata" do
    begin
      status_code, body = invoke_controller(
        UploadsController,
        :metadata,
        http_method: :post,
        params_hash: params.to_h.merge(json_params),
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/onebox_show" do
    begin
      status_code, body = invoke_controller(
        OneboxController,
        :show,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/inline_onebox_show" do
    begin
      p = json_params
      status_code, body = invoke_controller(
        InlineOneboxController,
        :show,
        http_method: :post,
        params_hash: p,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/search_query" do
    begin
      status_code, body = invoke_controller(
        SearchController,
        :query,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/search_show" do
    begin
      status_code, body = invoke_controller(
        SearchController,
        :show,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/search_click" do
    begin
      status_code, body = invoke_controller(
        SearchController,
        :click,
        http_method: :post,
        params_hash: json_params,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/topics_show" do
    begin
      status_code, body = invoke_controller(
        TopicsController,
        :show,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/topics_posts" do
    begin
      status_code, body = invoke_controller(
        TopicsController,
        :posts,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/topics_excerpts" do
    begin
      status_code, body = invoke_controller(
        TopicsController,
        :excerpts,
        http_method: :get,
        params_hash: params.to_h,
      )
      status status_code
      body.to_s
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end
end

HarnessServer.run! if __FILE__ == $PROGRAM_NAME
