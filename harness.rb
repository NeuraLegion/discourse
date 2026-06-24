require_relative "config/environment"
require "sinatra"
require "json"
require "stringio"
require "rack/multipart"
require "tempfile"

set :bind, "0.0.0.0"
set :port, 3001

helpers do
  def json_params
    request.content_type&.include?("application/json") ? (JSON.parse(request.body.read) rescue {}) : params
  end

  def app_controller(action_name)
    c = ApplicationController.new
    req = ActionDispatch::Request.new(request.env)
    res = ActionDispatch::Response.new

    c.set_request!(req)
    c.set_response!(res)
    c.params = params
    c.action_name = action_name.to_s if c.respond_to?(:action_name=)
    c
  end

  def with_controller(action_name)
    yield app_controller(action_name)
  rescue => e
    status 500
    body({ error: e.message }.to_json)
    halt
  end

  def parse_multipart_file
    if params[:file].is_a?(Hash) && params[:file][:tempfile]
      params[:file]
    elsif params[:file].respond_to?(:tempfile)
      params[:file]
    else
      nil
    end
  end
end

before do
  content_type :json if request.path != "/health"
end

get "/health" do
  status 200
  "ok"
end

post "/harness/create" do
  with_controller(:create) do |_c|
    file = parse_multipart_file
    result = UploadsController.create_upload(
      current_user: nil,
      file: file,
      url: params[:url],
      type: params[:upload_type] || params[:type],
      for_private_message: params[:for_private_message] == "true",
      for_site_setting: params[:for_site_setting] == "true",
      site_setting_name: params[:site_setting_name],
      pasted: params[:pasted] == "true",
      is_api: true,
      retain_hours: (params[:retain_hours] || 0).to_i
    )
    status 200
    result.is_a?(String) ? result : result.to_json
  end
end

get "/harness/show" do
  with_controller(:show) do |c|
    c.params = params
    c.request.env["PATH_INFO"] = request.path_info
    c.request.env["action_dispatch.request.path_parameters"] ||= {}
    c.request.env["action_dispatch.request.path_parameters"].merge!(
      controller: "uploads",
      action: "show"
    )
    out = UploadsController.new
    out.set_request!(c.request)
    out.set_response!(c.response)
    out.params = params
    out.show
    body c.response.body.join
    status c.response.status
  end
end

get "/harness/show_short" do
  with_controller(:show_short) do |c|
    out = UploadsController.new
    out.set_request!(c.request)
    out.set_response!(c.response)
    out.params = params
    out.show_short
    body c.response.body.join
    status c.response.status
  end
end

get "/harness/show_secure" do
  with_controller(:show_secure) do |c|
    out = UploadsController.new
    out.set_request!(c.request)
    out.set_response!(c.response)
    out.params = params
    out.show_secure
    body c.response.body.join
    status c.response.status
  end
end

post "/harness/metadata" do
  with_controller(:metadata) do |_c|
    result = UploadsController.new
    result.set_request!(request)
    result.set_response!(response)
    result.params = params
    result.metadata
    body response.body.join
    status response.status
  end
end

get "/harness/onebox_show" do
  with_controller(:show) do |_c|
    result = OneboxController.new
    result.set_request!(request)
    result.set_response!(response)
    result.params = params
    result.show
    body response.body.join
    status response.status
  end
end

get "/harness/embed_topics" do
  result = EmbedController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.topics
  body response.body.join
  status response.status
end

get "/harness/embed_comments" do
  result = EmbedController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.comments
  body response.body.join
  status response.status
end

get "/harness/permalink_show" do
  result = PermalinksController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.show
  body response.body.join
  status response.status
end

get "/harness/permalink_check" do
  result = PermalinksController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.check
  body response.body.join
  status response.status
end

get "/harness/static_show" do
  result = StaticController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.show
  body response.body.join
  status response.status
end

post "/harness/static_enter" do
  result = StaticController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.enter
  body response.body.join
  status response.status
end

get "/harness/robots_txt_show" do
  result = RobotsTxtController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.index
  body response.body.join
  status response.status
end

put "/harness/admin_robots_txt_update" do
  result = Admin::RobotsTxtController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.update
  body response.body.join
  status response.status
end

get "/harness/search_query" do
  result = SearchController.new
  result.set_request!(request)
  result.set_response!(response)
  result.params = params
  result.query
  body response.body.join
  status response.status
end

run! if app_file == $0
