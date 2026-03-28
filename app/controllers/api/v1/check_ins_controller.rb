# frozen_string_literal: true

module Api
  module V1
    class CheckInsController < ActionController::API
      before_action :set_content_type

      # GET/POST /api/v1/check_in/:token
      # No authentication required — token in URL is the auth, just like Dead Man's Snitch.
      def ping
        check_in = ActsAsTenant.without_tenant do
          CheckIn.find_by(identifier: params[:token], enabled: true)
        end

        if check_in
          ActsAsTenant.with_tenant(check_in.account) do
            check_in.record_success_ping!(source_ip: request.remote_ip)
          end
          render json: { status: "ok", message: "Check-in received", last_seen_at: check_in.last_seen_at.iso8601 }
        else
          render json: { status: "not_found", message: "Unknown or disabled check-in token" }, status: :not_found
        end
      rescue => e
        Rails.logger.error("[CheckIn::Ping] Error: #{e.message}")
        render json: { status: "error", message: "Internal error" }, status: :internal_server_error
      end

      private

      def set_content_type
        response.content_type = "application/json"
      end
    end
  end
end
