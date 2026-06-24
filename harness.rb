# frozen_string_literal: true

require "sinatra/base"
require "json"
require "uri"

require_relative "config/environment"

class HarnessServer < Sinatra::Base
  set :port, 3001
  set :bind, "0.0.0.0"

  before do
    content_type "text/plain"
  end

  def parse_bool(val)
    val == true || val.to_s == "true" || val.to_s == "1"
  end

  def parse_json_param(val)
    return val if val.is_a?(Hash) || val.is_a?(Array)
    return nil if val.nil? || val == ""

    JSON.parse(val)
  rescue JSON::ParserError
    val
  end

  def build_controller(klass)
    controller = klass.new

    req = Rack::Request.new(request.env)
    controller.request = ActionDispatch::Request.new(request.env)
    controller.response = ActionDispatch::Response.new
    controller.params = params.to_unsafe_h if params.respond_to?(:to_unsafe_h)
    controller.params ||= params
    controller
  end

  def invoke_controller_action(controller, action_name)
    controller.process(action_name)
  end

  def json_body
    request.body.rewind
    body = request.body.read
    return {} if body.nil? || body.strip.empty?

    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  get "/health" do
    status 200
    "ok"
  end

  post "/harness/create" do
    begin
      controller = build_controller(UploadsController)
      controller.params[:upload_type] ||= params["upload_type"] || json_body["upload_type"]
      controller.params[:url] ||= params["url"] || json_body["url"]
      controller.params[:file] ||= params["file"]
      controller.params[:type] ||= params["type"] || json_body["type"]
      controller.params[:retain_hours] ||= params["retain_hours"] || json_body["retain_hours"]
      controller.params[:pasted] ||= params["pasted"] || json_body["pasted"]
      controller.params[:for_private_message] ||= params["for_private_message"] || json_body["for_private_message"]
      controller.params[:for_site_setting] ||= params["for_site_setting"] || json_body["for_site_setting"]
      controller.params[:site_setting_name] ||= params["site_setting_name"] || json_body["site_setting_name"]

      result = UploadsController.create_upload(
        current_user: controller.send(:current_user),
        file: params["file"],
        url: params["url"] || json_body["url"],
        type: params["upload_type"] || params["type"] || json_body["upload_type"] || json_body["type"],
        for_private_message: parse_bool(params["for_private_message"] || json_body["for_private_message"]),
        for_site_setting: parse_bool(params["for_site_setting"] || json_body["for_site_setting"]),
        site_setting_name: params["site_setting_name"] || json_body["site_setting_name"],
        pasted: parse_bool(params["pasted"] || json_body["pasted"]),
        is_api: true,
        retain_hours: (params["retain_hours"] || json_body["retain_hours"] || 0).to_i,
      )
      status 200
      content_type "application/json"
      UploadsController.serialize_upload(result).to_json
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/show" do
    begin
      controller = build_controller(UploadsController)
      controller.params[:site] ||= params["site"]
      controller.params[:sha] ||= params["sha"]
      controller.params[:id] ||= params["id"]
      controller.params[:inline] ||= params["inline"]
      controller.request.env["PATH_INFO"] = request.path
      result = controller.show
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/show_short" do
    begin
      controller = build_controller(UploadsController)
      controller.params[:base62] ||= params["base62"]
      controller.params[:extension] ||= params["extension"]
      result = controller.show_short
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/show_secure" do
    begin
      controller = build_controller(UploadsController)
      controller.params[:path] ||= params["path"]
      controller.params[:extension] ||= params["extension"]
      result = controller.show_secure
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  post "/harness/metadata" do
    begin
      controller = build_controller(UploadsController)
      controller.params[:url] ||= params["url"] || json_body["url"]
      result = controller.metadata
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/query" do
    begin
      controller = build_controller(SearchController)
      controller.params[:term] ||= params["term"]
      controller.params[:type_filter] ||= params["type_filter"]
      controller.params[:search_for_id] ||= params["search_for_id"]
      controller.params[:search_context] ||= parse_json_param(params["search_context"])
      result = controller.query
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/show_search" do
    begin
      controller = build_controller(SearchController)
      controller.params[:q] ||= params["q"]
      controller.params[:page] ||= params["page"]
      result = controller.show
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  post "/harness/click" do
    begin
      controller = build_controller(SearchController)
      controller.params[:search_log_id] ||= params["search_log_id"] || json_body["search_log_id"]
      controller.params[:search_result_type] ||= params["search_result_type"] || json_body["search_result_type"]
      controller.params[:search_result_id] ||= params["search_result_id"] || json_body["search_result_id"]
      result = controller.click
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/embed_show" do
    begin
      controller = build_controller(EmbedController)
      controller.params[:topic_id] ||= params["topic_id"]
      controller.params[:embed_url] ||= params["embed_url"]
      controller.params[:full_app] ||= params["full_app"]
      result = controller.show
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/comments" do
    begin
      controller = build_controller(EmbedController)
      controller.params[:embed_url] ||= params["embed_url"]
      controller.params[:topic_id] ||= params["topic_id"]
      controller.params[:full_app] ||= params["full_app"]
      result = controller.comments
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/onebox_show" do
    begin
      controller = build_controller(OneboxController)
      controller.params[:url] ||= params["url"]
      controller.params[:refresh] ||= params["refresh"]
      controller.params[:category_id] ||= params["category_id"]
      controller.params[:topic_id] ||= params["topic_id"]
      result = controller.show
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/permalink_show" do
    begin
      controller = build_controller(PermalinksController)
      request.env["PATH_INFO"] = params["request.fullpath"] || request.path
      result = controller.show
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/permalink_check" do
    begin
      controller = build_controller(PermalinksController)
      controller.params[:path] ||= params["path"]
      result = controller.check
      result.nil? ? controller.response.body.join : controller.response.body.join
    rescue => e
      status 500
      e.message
    end
  end

  post "/harness/create_for" do
    begin
      file = params["file"]
      filename = params["filename"] || (file.respond_to?(:original_filename) ? file.original_filename : "upload")
      uc = UploadCreator.new(file&.tempfile || file, filename, {})
      result = uc.create_for((params["user_id"] || json_body["user_id"] || 1).to_i)
      status 200
      result.to_json
    rescue => e
      status 500
      e.message
    end
  end

  post "/harness/clean_svg" do
    begin
      uc = UploadCreator.new(params["file"]&.tempfile || params["file"], params["filename"] || "upload.svg", {})
      result = uc.clean_svg!
      status 200
      (result.nil? ? "ok" : result.to_s)
    rescue => e
      status 500
      e.message
    end
  end

  get "/harness/resolve" do
    begin
      result = FinalDestination.resolve(params["url"])
      status 200
      result.to_s
    rescue => e
      status 500
      e.message
    end
  end
end

HarnessServer.run!
