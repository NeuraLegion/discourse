# frozen_string_literal: true

# On initialize, reset flags cache
Rails.application.config.to_prepare do
  begin
    if Discourse.cache.is_a?(Cache) &&
         !ActiveRecord::Base.connection_pool.migration_context.needs_migration?
      Flag.reset_flag_settings!
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::DatabaseConnectionError, PG::Error
    # Database may be unavailable during bootstrap and multisite test DB setup.
  end
end
