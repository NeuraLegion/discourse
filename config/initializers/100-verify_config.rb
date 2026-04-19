# frozen_string_literal: true

# Check that the app is configured correctly. Raise some helpful errors if something is wrong.
# On this repository's production boot path, SiteSetting may not be loaded yet when this
# initializer runs, so skip hostname verification until the application is fully initialized.

if defined?(Rails::Server) && Rails.env.production? # Only run these checks when starting up a production server
  if defined?(SiteSetting) && %w[localhost production.localhost].include?(Discourse.current_hostname)
    puts <<~TEXT

      Discourse.current_hostname = '#{Discourse.current_hostname}'

      Please update the host_names property in config/database.yml
      so that it uses the hostname of your site. Otherwise you will
      experience problems, like links in emails using #{Discourse.current_hostname}.

    TEXT

    raise "Invalid host_names in database.yml"
  end

  assets_present = Dir.glob(File.join(Rails.root, "public", "assets", "*.js")).present?

  if !assets_present
    puts <<~TEXT

      Assets have not been precompiled. Please run the following command
      before starting the rails server in production mode:

          rake assets:precompile

    TEXT

    raise "Assets have not been precompiled"
  end
end
