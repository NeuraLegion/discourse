# frozen_string_literal: true

# Check that the app is configured correctly. Raise some helpful errors if something is wrong.
# In Rails 8 / Zeitwerk boot, SiteSetting may not yet be autoloaded when this initializer runs,
# so avoid calling Discourse.current_hostname here.

if defined?(Rails::Server) && Rails.env.production? # Only run these checks when starting up a production server
  current_hostname = RailsMultisite::ConnectionManagement.current_hostname

  if %w[localhost production.localhost].include?(current_hostname)
    puts <<~TEXT

      Discourse.current_hostname = '#{current_hostname}'

      Please update the host_names property in config/database.yml
      so that it uses the hostname of your site. Otherwise you will
      experience problems, like links in emails using #{current_hostname}.

    TEXT

    raise "Invalid host_names in database.yml"
  end

  if !Dir.glob(File.join(Rails.root, "public", "assets", "application*.js")).present?
    puts <<~TEXT

      Assets have not been precompiled. Please run the following command
      before starting the rails server in production mode:

          rake assets:precompile

    TEXT

    raise "Assets have not been precompiled"
  end
end
