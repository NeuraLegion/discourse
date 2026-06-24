# frozen_string_literal: true

require "sinatra/base"
require "json"
require "tempfile"
require "stringio"
require "rack/multipart"
require "rack/utils"

require_relative "config/environment"

class HarnessServer < Sinatra::Base
  set :port, 3001
  set :bind, "0.0.0.0"

  before do
    content_type "application/json"
  end

  helpers do
    def json_body
      request.body.rewind
      body = request.body.read
      body.nil? || body.empty? ? {} : JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def params_hash
      case request.media_type
      when "application/json"
        json_body
      else
        params.to_h
      end
    end

    def call_with_error_handling
      yield
    rescue => e
      status 500
      { error: e.message }.to_json
    end

    def render_result(result)
      status 200
      case result
      when String
        result
      else
        begin
          result.to_json
        rescue
          { result: result.to_s }.to_json
        end
      end
    end

    def build_upload_param(file_param)
      return nil if file_param.nil?

      if file_param.is_a?(Hash) && file_param[:tempfile]
        file_param
      elsif file_param.respond_to?(:tempfile) && file_param.respond_to?(:original_filename)
        { tempfile: file_param.tempfile, filename: file_param.original_filename, type: file_param.content_type }
      else
        nil
      end
    end
  end

  get "/health" do
    status 200
    { ok: true }.to_json
  end

  post "/harness/create" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      halt 500, { error: "No user available" }.to_json unless user

      file_param = build_upload_param(params["file"] || p["file"])

      result = UploadsController.create_upload(
        current_user: user,
        file: file_param && file_param[:tempfile],
        url: p["url"],
        type: (p["upload_type"] || p["type"] || "avatar").to_s,
        for_private_message: p["for_private_message"].to_s == "true",
        for_site_setting: p["for_site_setting"].to_s == "true",
        site_setting_name: p["site_setting_name"],
        pasted: p["pasted"].to_s == "true",
        is_api: true,
        retain_hours: (p["retain_hours"] || 0).to_i
      )

      render_result(UploadsController.serialize_upload(result))
    end
  end

  get "/harness/show_secure" do
    call_with_error_handling do
      p = params_hash
      controller = UploadsController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.show_secure
      response.body.join
    end
  end

  get "/harness/show_short" do
    call_with_error_handling do
      p = params_hash
      controller = UploadsController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.show_short
      response.body.join
    end
  end

  post "/harness/metadata" do
    call_with_error_handling do
      p = params_hash
      upload = Upload.get_from_url(p["url"])
      halt 500, { error: "Upload not found" }.to_json unless upload
      render_result({
        original_filename: upload.original_filename,
        width: upload.width,
        height: upload.height,
        human_filesize: upload.human_filesize
      })
    end
  end

  get "/harness/query" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = SearchController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.query
      response.body.join
    end
  end

  get "/harness/show" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = SearchController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.show
      response.body.join
    end
  end

  post "/harness/click" do
    call_with_error_handling do
      p = params_hash
      controller = SearchController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.click
      response.body.join
    end
  end

  get "/harness/onebox" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = OneboxController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.show
      response.body.join
    end
  end

  get "/harness/comments" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = EmbedController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.comments
      response.body.join
    end
  end

  get "/harness/topics" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = EmbedController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.topics
      response.body.join
    end
  end

  get "/harness/check" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = PermalinksController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.check
      response.body.join
    end
  end

  get "/harness/show_permalink" do
    call_with_error_handling do
      user = User.first || User.find_by(id: 1)
      controller = PermalinksController.new
      controller.request = request
      controller.response = response
      controller.instance_variable_set(:@current_user, user)
      controller.show
      response.body.join
    end
  end

  post "/harness/inline_onebox" do
    call_with_error_handling do
      p = params_hash
      user = User.first || User.find_by(id: 1)
      controller = InlineOneboxController.new
      controller.request = request
      controller.response = response
      controller.params.merge!(p)
      controller.instance_variable_set(:@current_user, user)
      controller.show
      response.body.join
    end
  end

  post "/harness/upload_creator" do
    call_with_error_handling do
      p = params_hash
      file = params["file"]
      halt 400, { error: "file required" }.to_json unless file && file[:tempfile]

      creator = UploadCreator.new(file[:tempfile], file[:filename] || file[:original_filename], {})
      result = creator.create_for((p["user_id"] || 1).to_i)
      render_result(result.as_json)
    end
  end

  get "/harness/external_onebox" do
    call_with_error_handling do
      p = params_hash
      render_result(Oneboxer.external_onebox(p["url"], p["available_strategies"] || []))
    end
  end

  get "/harness/resolve" do
    call_with_error_handling do
      p = params_hash
      render_result(FinalDestination.resolve(p["url"]).to_s)
    end
  end

  get "/harness/search_execute" do
    call_with_error_handling do
      p = params_hash
      render_result(Search.execute(p["term"]).as_json)
    end
  end
end

HarnessServer.run!
