require "sinatra"
require "json"
require "stringio"
require_relative "config/environment"

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
    return {} if body.nil? || body.strip.empty?
    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def call_action(klass, action, params_hash = {})
    controller = klass.new
    env = Rack::MockRequest.env_for("/", method: request.request_method)
    env["rack.input"] = StringIO.new(request.body.string rescue "")
    env["REQUEST_METHOD"] = request.request_method
    env["PATH_INFO"] = request.path_info
    env["QUERY_STRING"] = request.query_string.to_s
    env["action_dispatch.request.parameters"] = params_hash
    controller.set_request!(ActionDispatch::Request.new(env)) if controller.respond_to?(:set_request!)
    controller.set_response!(ActionDispatch::Response.new) if controller.respond_to?(:set_response!)
    controller.params.merge!(params_hash) if controller.respond_to?(:params)
    controller.process(action)
  end

  def invoke_controller(controller_class, action_name, path_params = {}, body_params = {})
    controller = controller_class.new

    env = Rack::MockRequest.env_for(request.url, method: request.request_method)
    env["action_dispatch.request.path_parameters"] = {
      controller: controller_class.name.underscore.gsub("/", "_"),
      action: action_name.to_s
    }.merge(path_params)

    req = ActionDispatch::Request.new(env)
    controller.request = req
    controller.response = ActionDispatch::Response.new
    controller.params.merge!(path_params)
    controller.params.merge!(req.GET)
    controller.params.merge!(body_params)

    begin
      result = controller.public_send(action_name)
      if controller.response.body.present?
        controller.response.body.join
      elsif result.is_a?(String)
        result
      else
        result.to_s
      end
    rescue => e
      halt 500, { error: e.message }.to_json
    end
  end
end

get "/harness/show" do
  invoke_controller(
    UploadsController,
    :show,
    { "site" => params["site"], "sha" => params["sha"], "id" => params["id"], "extension" => params["extension"] }
  )
end

get "/harness/show-short" do
  invoke_controller(
    UploadsController,
    :show_short,
    { "base62" => params["base62"], "extension" => params["extension"] }
  )
end

get "/harness/show-secure" do
  invoke_controller(
    UploadsController,
    :show_secure,
    { "path" => params["path"], "extension" => params["extension"] }
  )
end

post "/harness/create" do
  body = params.merge(json_params)
  invoke_controller(
    UploadsController,
    :create,
    {},
    {
      "upload_type" => body["upload_type"],
      "url" => body["url"],
      "file" => body["file"],
      "retain_hours" => body["retain_hours"]
    }
  )
end

post "/harness/metadata" do
  body = params.merge(json_params)
  invoke_controller(UploadsController, :metadata, {}, { "url" => body["url"] })
end

get "/harness/query" do
  invoke_controller(
    SearchController,
    :query,
    { "term" => params["term"], "type_filter" => params["type_filter"], "search_for_id" => params["search_for_id"] }
  )
end

get "/harness/search-show" do
  invoke_controller(SearchController, :show, { "q" => params["q"], "page" => params["page"] })
end

post "/harness/click" do
  invoke_controller(
    SearchController,
    :click,
    { "search_log_id" => params["search_log_id"], "search_result_type" => params["search_result_type"], "search_result_id" => params["search_result_id"] }
  )
end

get "/harness/search-users" do
  invoke_controller(
    UsersController,
    :search_users,
    {
      "term" => params["term"],
      "usernames" => params["usernames"],
      "group" => params["group"],
      "limit" => params["limit"]
    }
  )
end

post "/harness/users-create" do
  invoke_controller(
    UsersController,
    :create,
    {},
    {
      "email" => params["email"],
      "username" => params["username"],
      "password" => params["password"],
      "invite_code" => params["invite_code"]
    }
  )
end

put "/harness/users-update" do
  body = json_params
  invoke_controller(
    UsersController,
    :update,
    {},
    {
      "username" => body["username"],
      "user_fields" => body["user_fields"],
      "external_ids" => body["external_ids"]
    }
  )
end

post "/harness/revoke-account" do
  invoke_controller(
    UsersController,
    :revoke_account,
    {},
    { "provider_name" => params["provider_name"], "skip_remote" => params["skip_remote"] }
  )
end

get "/harness/lookup-search-context" do
  body = json_params
  invoke_controller(
    SearchController,
    :lookup_search_context,
    {},
    {
      "search_context" => body["search_context"],
      "context" => body["context"],
      "context_id" => body["context_id"]
    }
  )
end

get "/harness/admin-permalinks-index" do
  invoke_controller(Admin::PermalinksController, :index, { "filter" => params["filter"] })
end

post "/harness/admin-permalinks-create" do
  body = json_params
  invoke_controller(Admin::PermalinksController, :create, {}, { "permalink" => body["permalink"] })
end

post "/harness/normalize-url" do
  body = json_params
  begin
    Permalink.normalize_url(body["url"]).to_s
  rescue => e
    halt 500, { error: e.message }.to_json
  end
end

run! if app_file == $0
