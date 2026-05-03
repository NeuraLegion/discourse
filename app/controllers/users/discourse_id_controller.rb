# frozen_string_literal: true

class Users::DiscourseIdController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:revoke]
  skip_before_action :redirect_to_login_if_required,
                     :redirect_to_profile_if_required,
                     only: [:revoke]

  def revoke
    identifier = params[:identifier].to_s
    raise Discourse::InvalidParameters.new(:identifier) if identifier.blank? || identifier.length > 256
    raise Discourse::InvalidParameters.new(:identifier) if identifier !~ /\A[a-zA-Z0-9._\-]+\z/

    RateLimiter.new(nil, "discourse_id_revoke_#{identifier}", 5, 1.minute).performed!

    DiscourseId::Revoke.call(service_params) do |result|
      on_success { render json: { success: true } }
      on_failed_contract do |contract|
        logger.warn(result.inspect_steps) if SiteSetting.discourse_id_verbose_logging
        render json: { error: contract.errors.full_messages.join(", ") }, status: :bad_request
      end
      on_failure do
        logger.warn(result.inspect_steps) if SiteSetting.discourse_id_verbose_logging
        render json: { error: "Invalid request" }, status: :bad_request
      end
    end
  end

  private

  def service_params
    {
      params: {
        identifier: params[:identifier].to_s,
      },
      guardian:,
    }
  end
end
