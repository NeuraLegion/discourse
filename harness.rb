require "sinatra"
require "json"
require "stringio"

require_relative "config/environment"

set :bind, "0.0.0.0"
set :port, 3001

before do
  content_type "application/json"
end

helpers do
  def parsed_params
    request.params
  end

  def call_controller(controller_class, action_name)
    controller = controller_class.new
    env = Rack::MockRequest.env_for(request.url, method: request.request_method)
    env["rack.input"] = StringIO.new(request.body.read.to_s)
    env["REQUEST_METHOD"] = request.request_method
    env["QUERY_STRING"] = request.query_string.to_s
    env["REMOTE_ADDR"] = request.ip
    env["HTTP_USER_AGENT"] = request.user_agent.to_s if request.user_agent

    controller.request = ActionDispatch::Request.new(env)
    controller.response = ActionDispatch::Response.new
    controller.params.merge!(parsed_params)

    begin
      controller.process(action_name)
      body = controller.response.body
      body = body.join if body.respond_to?(:join)
      status controller.response.status
      headers controller.response.headers
      [status, headers, body.to_s]
    rescue => e
      [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
    end
  end

  def with_controller(controller_class, action_name)
    call_controller(controller_class, action_name)
  end
end

get "/health" do
  status 200
  { ok: true }.to_json
end

get "/harness/show" do
  begin
    with_controller(SearchController, :show)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/query" do
  begin
    with_controller(SearchController, :query)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

post "/harness/click" do
  begin
    with_controller(SearchController, :click)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

post "/harness/create" do
  begin
    with_controller(UploadsController, :create)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

post "/harness/lookup_urls" do
  begin
    with_controller(UploadsController, :lookup_urls)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/show_upload" do
  begin
    with_controller(UploadsController, :show)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/show_short" do
  begin
    with_controller(UploadsController, :show_short)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/show_secure" do
  begin
    with_controller(UploadsController, :show_secure)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/onebox_show" do
  begin
    with_controller(OneboxController, :show)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/inline_onebox_show" do
  begin
    with_controller(InlineOneboxController, :show)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/embed_comments" do
  begin
    with_controller(EmbedController, :comments)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/embed_topics" do
  begin
    with_controller(EmbedController, :topics)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/permalinks_show" do
  begin
    with_controller(PermalinksController, :show)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/permalinks_check" do
  begin
    with_controller(PermalinksController, :check)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

get "/harness/notifications_index" do
  begin
    with_controller(NotificationsController, :index)
  rescue => e
    [500, { "Content-Type" => "application/json" },({ error: e.message }.to_json)]
  end
end

run Sinatra::Application
