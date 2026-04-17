# frozen_string_literal: true

require "sinatra/base"
require "json"
require "rack/multipart"
require "stringio"

# Boot Rails/ActiveRecord/models/services without starting the web server
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
      body = request.body.read
      body.nil? || body.empty? ? {} : JSON.parse(body)
    rescue JSON::ParserError
      {}
    end

    def param_hash
      json_body.merge(params.to_h)
    end

    def with_controller(controller_class, action_name, http_method: "GET")
      controller = controller_class.new
      env = request.env

      # Make sure Rails request/response objects exist
      controller.set_request!(ActionDispatch::Request.new(env))
      controller.set_response!(ActionDispatch::Response.new)

      # Populate params for the action
      controller.params.merge!(params.to_h)

      # Stub common controller bits minimally
      allow_nil_methods = %i[
        current_user guardian is_api? session server_session request_site_current_user
      ]

      allow_nil_methods.each do |m|
        if controller.respond_to?(m)
          controller.define_singleton_method(m) { nil }
        end
      end

      result = controller.public_send(action_name)
      response.status = controller.response.status || 200

      if controller.response.body.respond_to?(:join)
        controller.response.body.join
      else
        result.nil? ? "" : result.to_s
      end
    rescue => e
      response.status = 500
      { error: e.class.name, message: e.message }.to_json
    end
  end

  # UploadsController.create(upload_type, url, file, pasted, for_private_message, for_site_setting, site_setting_name, retain_hours)
  post "/harness/create" do
    begin
      controller = UploadsController.new
      controller.set_request!(ActionDispatch::Request.new(request.env))
      controller.set_response!(ActionDispatch::Response.new)
      controller.params.merge!(params.to_h)

      # Provide a minimal current_user-like object for the real code path.
      me = Struct.new(:id, :admin?).new(1, true)
      controller.define_singleton_method(:current_user) { me }
      controller.define_singleton_method(:is_api?) { true }
      controller.define_singleton_method(:guardian) { nil }
      controller.define_singleton_method(:hijack) { |&blk| blk.call }

      # Invoke the real class method directly
      info = UploadsController.create_upload(
        current_user: me,
        file: params[:file],
        url: params[:url],
        type: (params[:upload_type] || params[:type] || "avatar").to_s,
        for_private_message: params[:for_private_message] == "true",
        for_site_setting: params[:for_site_setting] == "true",
        site_setting_name: params[:site_setting_name],
        pasted: params[:pasted] == "true",
        is_api: true,
        retain_hours: params[:retain_hours].to_i
      )

      status 200
      if UploadsController.respond_to?(:serialize_upload)
        UploadsController.serialize_upload(info).to_json
      else
        info.to_json
      end
    rescue => e
      status 500
      { error: e.class.name, message: e.message }.to_json
    end
  end

  # UploadsController.show(site, sha, id, inline)
  get "/harness/show" do
    with_controller(UploadsController, :show, http_method: "GET")
  end

  # UploadsController.show_short(base62, extension, inline)
  get "/harness/show_short" do
    with_controller(UploadsController, :show_short, http_method: "GET")
  end

  # UploadsController.show_secure(path, extension)
  get "/harness/show_secure" do
    with_controller(UploadsController, :show_secure, http_method: "GET")
  end

  # UploadsController.metadata(url)
  post "/harness/metadata" do
    with_controller(UploadsController, :metadata, http_method: "POST")
  end

  # SearchController.query(term, type_filter, search_for_id, restrict_to_archetype, context, context_id, skip_context)
  get "/harness/query" do
    with_controller(SearchController, :query, http_method: "GET")
  end

  # SearchController.show(q, page)
  get "/harness/show_search" do
    with_controller(SearchController, :show, http_method: "GET")
  end

  # SearchController.click(search_log_id, search_result_type, search_result_id)
  post "/harness/click" do
    with_controller(SearchController, :click, http_method: "POST")
  end

  # TagsController.search(q, limit, categoryId, selected_tag_ids, selected_tags, filterForInput, excludeSynonyms, excludeHasSynonyms)
  get "/harness/tags_search" do
    with_controller(TagsController, :search, http_method: "GET")
  end

  # Admin::SearchController.index(filter_names, filter_area, plugin, categories)
  get "/harness/admin_search" do
    with_controller(Admin::SearchController, :index, http_method: "GET")
  end

  # UsersController.search_users(...)
  get "/harness/search_users" do
    with_controller(UsersController, :search_users, http_method: "GET")
  end

  # UsersController.check_username(username, email, for_user_id)
  get "/harness/check_username" do
    with_controller(UsersController, :check_username, http_method: "GET")
  end

  # UsersController.check_email(email)
  get "/harness/check_email" do
    with_controller(UsersController, :check_email, http_method: "GET")
  end

  # InvitesController.create_multiple(...)
  post "/harness/create_multiple" do
    with_controller(InvitesController, :create_multiple, http_method: "POST")
  end

  # Optional generic route for quick debugging
  post "/harness/uploads_create" do
    with_controller(UploadsController, :create, http_method: "POST")
  end
end

BrightHarness.run!
