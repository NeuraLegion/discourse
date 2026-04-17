require "sinatra"
require "json"
require "rack/multipart"
require "stringio"

begin
  require_relative "config/environment"
rescue LoadError
  require_relative "./config/environment"
end

set :bind, "0.0.0.0"
set :port, 3001

helpers do
  def json_body
    request.body.rewind
    body = request.body.read
    body.nil? || body.empty? ? {} : JSON.parse(body)
  rescue JSON::ParserError
    {}
  end

  def params_hash
    request.GET.merge(request.POST)
  end

  def call_target
    yield
  rescue => e
    status 500
    content_type "text/plain"
    e.message.to_s
  end

  def render_result(result)
    content_type "application/json"
    case result
    when String
      result
    else
      JSON.generate(result)
    end
  end
end

before do
  content_type "application/json" if request.path_info == "/health" || request.path_info.start_with?("/harness/")
end

get "/health" do
  status 200
  "ok"
end

post "/harness/create" do
  call_target do
    p = params_hash
    upload_type = p["upload_type"]
    type = p["type"]
    url = p["url"]
    file = params["file"]
    files = params["files"]

    upload_param = file
    upload_param ||= files.first if files.respond_to?(:first)

    current_user = respond_to?(:current_user) ? current_user : nil
    current_user ||= (defined?(User) ? User.first : nil)

    result = UploadsController.create_upload(
      current_user: current_user || OpenStruct.new(id: 1, admin?: true),
      file: upload_param,
      url: url,
      type: (upload_type || type || "avatar"),
      for_private_message: p["for_private_message"] == "true",
      for_site_setting: p["for_site_setting"] == "true",
      site_setting_name: p["site_setting_name"],
      pasted: p["pasted"] == "true",
      is_api: true,
      retain_hours: (p["retain_hours"] || "0").to_i
    )
    render_result(UploadsController.serialize_upload(result))
  end
end

get "/harness/show" do
  call_target do
    controller = UploadsController.new
    controller.params.merge!(params_hash)
    result = controller.show
    render_result(result || { ok: true })
  end
end

get "/harness/show_short" do
  call_target do
    controller = UploadsController.new
    controller.params.merge!(params_hash)
    result = controller.show_short
    render_result(result || { ok: true })
  end
end

get "/harness/show_secure" do
  call_target do
    controller = UploadsController.new
    controller.params.merge!(params_hash)
    result = controller.show_secure
    render_result(result || { ok: true })
  end
end

post "/harness/metadata" do
  call_target do
    controller = UploadsController.new
    controller.params.merge!(params_hash)
    result = controller.metadata
    render_result(result || { ok: true })
  end
end

get "/harness/search_show" do
  call_target do
    controller = SearchController.new
    controller.params.merge!(params_hash)
    result = controller.show
    render_result(result || { ok: true })
  end
end

get "/harness/search_query" do
  call_target do
    controller = SearchController.new
    controller.params.merge!(params_hash)
    result = controller.query
    render_result(result || { ok: true })
  end
end

post "/harness/search_click" do
  call_target do
    controller = SearchController.new
    controller.params.merge!(params_hash)
    result = controller.click
    render_result(result || { ok: true })
  end
end

get "/harness/permalink_show" do
  call_target do
    controller = PermalinksController.new
    controller.params.merge!(params_hash)
    result = controller.show
    render_result(result || { ok: true })
  end
end

get "/harness/permalink_check" do
  call_target do
    controller = PermalinksController.new
    controller.params.merge!(params_hash)
    result = controller.check
    render_result(result || { ok: true })
  end
end

get "/harness/onebox_show" do
  call_target do
    controller = OneboxController.new
    controller.params.merge!(params_hash)
    result = controller.show
    render_result(result || { ok: true })
  end
end

get "/harness/embed_topics" do
  call_target do
    controller = EmbedController.new
    controller.params.merge!(params_hash)
    result = controller.topics
    render_result(result || { ok: true })
  end
end

get "/harness/embed_comments" do
  call_target do
    controller = EmbedController.new
    controller.params.merge!(params_hash)
    result = controller.comments
    render_result(result || { ok: true })
  end
end

get "/harness/stylesheets_show_resource" do
  call_target do
    controller = StylesheetsController.new
    controller.params.merge!(params_hash)
    result = controller.show_resource
    render_result(result || { ok: true })
  end
end

get "/harness/stylesheets_color_scheme" do
  call_target do
    controller = StylesheetsController.new
    controller.params.merge!(params_hash)
    result = controller.color_scheme
    render_result(result || { ok: true })
  end
end

get "/harness/robots_index" do
  call_target do
    controller = RobotsTxtController.new
    controller.params.merge!(params_hash)
    result = controller.index
    render_result(result || { ok: true })
  end
end

run! if app_file == $0
