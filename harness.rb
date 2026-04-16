# frozen_string_literal: true

require "json"
require "sinatra"
require "tempfile"
require "rack/test"
require "uri"

require_relative "config/environment"

set :bind, "0.0.0.0"
set :port, 3001
set :show_exceptions, false
set :raise_errors, false

module HarnessHelpers
  module_function

  def bool_param(value)
    case value
    when true, "true", "1", 1, "on", "yes" then true
    else false
    end
  end

  def int_param(value)
    return nil if value.nil? || value == ""
    value.to_i
  end

  def json_param(value, default = nil)
    return default if value.nil? || value == ""
    value.is_a?(String) ? JSON.parse(value) : value
  end

  def uploaded_file_from_param(param)
    return nil if param.nil?

    if param.respond_to?(:tempfile) && param.respond_to?(:original_filename)
      param
    elsif param.is_a?(Hash) && param[:tempfile]
      Rack::Test::UploadedFile.new(
        param[:tempfile].path,
        param[:type] || "application/octet-stream",
        original_filename: param[:filename] || File.basename(param[:tempfile].path),
      )
    else
      nil
    end
  end

  def fixture_admin_user
    User.where(admin: true).order(:id).first || User.find_by(username: "admin") || User.first
  end

  def any_user
    fixture_admin_user || User.order(:id).first
  end

  def guardian_for_user(user = nil)
    Guardian.new(user)
  end

  def serialize_result(obj)
    case obj
    when nil
      ""
    when String
      obj
    else
      if defined?(UploadsController) && obj.is_a?(Upload)
        UploadsController.serialize_upload(obj).to_json
      elsif obj.respond_to?(:as_json)
        obj.as_json.to_json
      else
        obj.inspect
      end
    end
  end

  def build_controller(klass, user: nil, params_hash: {}, env_overrides: {})
    env = Rack::MockRequest.env_for("/")
    env["REQUEST_METHOD"] = "GET"
    env["rack.input"] = StringIO.new("")
    env["REMOTE_ADDR"] = "127.0.0.1"
    env["HTTP_USER_AGENT"] = "bright-harness"
    env.merge!(env_overrides)
    request = ActionDispatch::Request.new(env)
    response = ActionDispatch::Response.new

    controller = klass.new
    controller.set_request!(request)
    controller.set_response!(response)
    controller.params = ActionController::Parameters.new(params_hash)
    controller.instance_variable_set(:@_params, controller.params)
    controller.define_singleton_method(:current_user) { user }
    controller
  end

  def with_hijack_passthrough(controller)
    controller.define_singleton_method(:hijack) do |*_args, &blk|
      instance_exec(&blk)
    end
    controller
  end

  def render_output(controller)
    body = controller.response&.body
    body.is_a?(Array) ? body.join : body.to_s
  end
end

before do
  content_type "text/plain"
end

get "/health" do
  status 200
  "ok"
end

post "/harness/create-upload" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.fixture_admin_user
      end

    result =
      UploadsController.create_upload(
        current_user: user,
        file: HarnessHelpers.uploaded_file_from_param(params["file"]),
        url: params["url"],
        type: params["type"] || "composer",
        for_private_message: HarnessHelpers.bool_param(params["for_private_message"]),
        for_site_setting: HarnessHelpers.bool_param(params["for_site_setting"]),
        site_setting_name: params["site_setting_name"],
        pasted: HarnessHelpers.bool_param(params["pasted"]),
        is_api: params.key?("is_api") ? HarnessHelpers.bool_param(params["is_api"]) : true,
        retain_hours: HarnessHelpers.int_param(params["retain_hours"]) || 0,
      )

    HarnessHelpers.serialize_result(result)
  rescue => e
    status 500
    e.message
  end
end

get "/harness/onebox-show" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.any_user
      end

    controller =
      HarnessHelpers.build_controller(
        OneboxController,
        user: user,
        params_hash: {
          url: params["url"] || "http://127.0.0.1/",
          refresh: params["refresh"] || "true",
          category_id: HarnessHelpers.int_param(params["category_id"]) || 1,
          topic_id: HarnessHelpers.int_param(params["topic_id"]) || 1,
        },
      )

    HarnessHelpers.with_hijack_passthrough(controller)
    controller.show
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

post "/harness/web-hook-emitter-emit" do
  begin
    payload_url = params["payload_url"] || params["url"] || "http://127.0.0.1/"
    webhook =
      WebHook.create!(
        name: "harness",
        payload_url: payload_url,
        content_type: "application/json",
        verify_certificate: false,
        active: true,
      )

    webhook_event = WebHookEvent.create!(web_hook: webhook)

    emitter = WebHookEmitter.new(webhook, webhook_event)
    response =
      emitter.emit!(
        headers: HarnessHelpers.json_param(params["headers"], { "Content-Type" => "application/json" }),
        body: params["body"] || "{\"ping\":true}",
      )

    response ? "#{response.status}\n#{response.body}" : webhook_event.reload.response_headers.to_s
  rescue => e
    status 500
    e.message
  end
end

post "/harness/admin-themes-import" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.fixture_admin_user
      end

    controller =
      HarnessHelpers.build_controller(
        Admin::ThemesController,
        user: user,
        params_hash: {
          remote: params["remote"],
          branch: params["branch"],
          public_key: params["public_key"],
          bundle: HarnessHelpers.uploaded_file_from_param(params["bundle"]),
          theme: HarnessHelpers.uploaded_file_from_param(params["theme"]),
          force: HarnessHelpers.bool_param(params["force"]),
        },
      )

    HarnessHelpers.with_hijack_passthrough(controller)
    controller.import
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

put "/harness/admin-themes-update-source" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.fixture_admin_user
      end

    controller =
      HarnessHelpers.build_controller(
        Admin::ThemesController,
        user: user,
        params_hash: {
          id: HarnessHelpers.int_param(params["id"]) || 1,
          remote_url: params["remote_url"] || "https://example.com/theme.git",
          branch: params["branch"],
          public_key: params["public_key"],
        },
      )

    HarnessHelpers.with_hijack_passthrough(controller)
    controller.update_source
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

get "/harness/embed-comments" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        nil
      end

    referer = params["referer"] || params["embed_url"] || "https://example.com/post"

    controller =
      HarnessHelpers.build_controller(
        EmbedController,
        user: user,
        params_hash: {
          embed_url: params["embed_url"],
          topic_id: params["topic_id"],
          full_app: params["full_app"],
        },
        env_overrides: {
          "HTTP_REFERER" => referer,
        },
      )

    controller.comments
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

post "/harness/invites-upload-csv" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.fixture_admin_user
      end

    controller =
      HarnessHelpers.build_controller(
        InvitesController,
        user: user,
        params_hash: {
          file: HarnessHelpers.uploaded_file_from_param(params["file"]),
          files: [HarnessHelpers.uploaded_file_from_param(params["file"])].compact,
        },
      )

    HarnessHelpers.with_hijack_passthrough(controller)
    controller.upload_csv
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

post "/harness/tags-upload" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.fixture_admin_user
      end

    controller =
      HarnessHelpers.build_controller(
        TagsController,
        user: user,
        params_hash: {
          file: HarnessHelpers.uploaded_file_from_param(params["file"]),
          files: [HarnessHelpers.uploaded_file_from_param(params["file"])].compact,
        },
      )

    HarnessHelpers.with_hijack_passthrough(controller)
    controller.upload
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

post "/harness/admin-backups-upload-backup-chunk" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.fixture_admin_user
      end

    controller =
      HarnessHelpers.build_controller(
        Admin::BackupsController,
        user: user,
        params_hash: {
          resumableFilename: params["resumableFilename"] || "backup.tar.gz",
          resumableTotalSize: HarnessHelpers.int_param(params["resumableTotalSize"]) || 1_048_576,
          resumableIdentifier: params["resumableIdentifier"] || "abc123",
          resumableChunkNumber: HarnessHelpers.int_param(params["resumableChunkNumber"]) || 1,
          resumableChunkSize: HarnessHelpers.int_param(params["resumableChunkSize"]) || 524_288,
          resumableCurrentChunkSize: HarnessHelpers.int_param(params["resumableCurrentChunkSize"]) || 524_288,
          file: HarnessHelpers.uploaded_file_from_param(params["file"]),
        },
      )

    controller.upload_backup_chunk
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

post "/harness/handle-chunk-upload-upload-chunk" do
  begin
    chunk = params["chunk"] || "/tmp/uploads/chunk-1.part"
    file = HarnessHelpers.uploaded_file_from_param(params["file"])
    HandleChunkUpload.upload_chunk(chunk, file: file)
    "ok"
  rescue => e
    status 500
    e.message
  end
end

get "/harness/search-query" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.any_user
      end

    search_context = HarnessHelpers.json_param(params["search_context"], nil)

    controller =
      HarnessHelpers.build_controller(
        SearchController,
        user: user,
        params_hash: {
          term: params["term"] || "test OR 1=1",
          type_filter: params["type_filter"],
          restrict_to_archetype: params["restrict_to_archetype"],
          search_context: search_context,
        },
      )

    controller.query
    HarnessHelpers.render_output(controller)
  rescue => e
    status 500
    e.message
  end
end

get "/harness/tags-search-search" do
  begin
    user =
      if params["current_user_id"]
        User.find(params["current_user_id"].to_i)
      else
        HarnessHelpers.any_user
      end

    guardian = HarnessHelpers.guardian_for_user(user)
    service_params =
      HarnessHelpers.json_param(
        params["params"],
        {
          "q" => params["q"] || "adm",
          "limit" => HarnessHelpers.int_param(params["limit"]) || 20,
          "selected_tag_ids" => HarnessHelpers.json_param(params["selected_tag_ids"], [1]),
          "filterForInput" => params.key?("filterForInput") ? HarnessHelpers.bool_param(params["filterForInput"]) : true,
        },
      )

    result = Tags::Search.call(guardian: guardian, params: service_params)
    result.respond_to?(:to_h) ? result.to_h.to_json : result.inspect
  rescue => e
    status 500
    e.message
  end
end

error do
  e = env["sinatra.error"]
  status 500
  e.message
end
