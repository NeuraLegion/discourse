# frozen_string_literal: true

require "sinatra/base"
require "json"
require "rack/multipart"
require "stringio"

# Boot Rails models/services without starting the app web server
require_relative "config/environment"

class BrightHarness < Sinatra::Base
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
    def json_body
      request.body.rewind
      raw = request.body.read
      raw.empty? ? {} : JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def call_controller(controller_class, action_name, params_hash = {}, method: :get, multipart: false)
      controller = controller_class.new

      env = {
        "rack.input" => StringIO.new(""),
        "REQUEST_METHOD" => method.to_s.upcase,
        "PATH_INFO" => request.path_info,
        "QUERY_STRING" => request.query_string.to_s,
        "rack.url_scheme" => "http",
        "HTTP_HOST" => "localhost:3001",
        "REMOTE_ADDR" => request.ip,
        "action_dispatch.show_exceptions" => false,
      }

      env["CONTENT_TYPE"] = request.content_type if request.content_type
      env["CONTENT_LENGTH"] = request.content_length.to_s if request.content_length

      req = ActionDispatch::Request.new(env)
      params_obj = ActionController::Parameters.new(params_hash)
      controller.set_request!(req)
      controller.set_response!(ActionDispatch::Response.new)
      controller.params = params_obj

      result = controller.send(action_name)
      body =
        if controller.response&.body.present?
          controller.response.body
        else
          result
        end

      [controller.response.status, body]
    end

    def render_result(status, body)
      status status
      if body.is_a?(String)
        body
      elsif body.respond_to?(:to_json)
        body.to_json
      else
        { result: body }.to_json
      end
    end
  end

  post "/harness/create" do
    begin
      params_hash = json_body
      status_code, result = call_controller(UploadsController, :create, params_hash, method: :post)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show" do
    begin
      status_code, result = call_controller(UploadsController, :show, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show_short" do
    begin
      status_code, result = call_controller(UploadsController, :show_short, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/_show_secure_deprecated" do
    begin
      status_code, result =
        call_controller(UploadsController, :show_secure, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/show_secure" do
    begin
      status_code, result = call_controller(UploadsController, :show_secure, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/metadata" do
    begin
      status_code, result = call_controller(UploadsController, :metadata, json_body, method: :post)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/onebox_show" do
    begin
      status_code, result = call_controller(OneboxController, :show, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/embed_show" do
    begin
      status_code, result = call_controller(EmbedController, :comments, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/embed_topics" do
    begin
      status_code, result = call_controller(EmbedController, :topics, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/search_query" do
    begin
      status_code, result = call_controller(SearchController, :query, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/search_show" do
    begin
      status_code, result = call_controller(SearchController, :show, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/search_click" do
    begin
      status_code, result = call_controller(SearchController, :click, json_body, method: :post)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/invites_create" do
    begin
      status_code, result = call_controller(InvitesController, :create, json_body, method: :post)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/invites_create_multiple" do
    begin
      status_code, result =
        call_controller(InvitesController, :create_multiple, json_body, method: :post)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  post "/harness/invites_upload_csv" do
    begin
      status_code, result = call_controller(InvitesController, :upload_csv, params.to_h, method: :post)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end

  get "/harness/permalinks_check" do
    begin
      status_code, result = call_controller(PermalinksController, :check, params.to_h, method: :get)
      render_result(status_code, result)
    rescue => e
      status 500
      { error: e.message }.to_json
    end
  end
end

BrightHarness.run!
