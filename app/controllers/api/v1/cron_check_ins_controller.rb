# frozen_string_literal: true

module Api
  module V1
    # Authenticated cron / heartbeat check-ins (Sentry-style): project token + monitor slug.
    class CronCheckInsController < Api::BaseController
      CRON_STATUSES = %w[ok success in_progress error].freeze

      def create
        unless @current_project
          render json: { error: "project_not_found", message: "Project not found" }, status: :not_found
          return
        end

        slug = params[:slug].to_s.strip.downcase
        if slug.blank?
          render json: { error: "bad_request", message: "slug is required" }, status: :bad_request
          return
        end

        status = params[:status].to_s.strip.downcase
        if status.blank?
          status = "ok"
        end

        unless CRON_STATUSES.include?(status)
          render json: {
            error: "bad_request",
            message: "status must be one of: ok, success, in_progress, error"
          }, status: :bad_request
          return
        end

        check_in = @current_project.check_ins.enabled.find_by(slug: slug)
        unless check_in
          render json: { error: "not_found", message: "Unknown or disabled check-in slug" }, status: :not_found
          return
        end

        case status
        when "ok", "success"
          ActsAsTenant.with_tenant(check_in.account) do
            check_in.update_column(:run_started_at, nil) if check_in.run_started_at.present?
            check_in.record_success_ping!(source_ip: request.remote_ip)
          end
          check_in.reload
          render json: {
            status: "ok",
            message: "Check-in received",
            last_seen_at: check_in.last_seen_at&.iso8601
          }
        when "in_progress"
          ActsAsTenant.with_tenant(check_in.account) do
            check_in.update!(run_started_at: Time.current)
          end
          render json: { status: "ok", message: "Run started recorded" }
        when "error"
          render json: { status: "ok", message: "Error acknowledged" }
        end
      rescue => e
        Rails.logger.error("[CronCheckIns] Error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: "internal_error", message: "Internal error" }, status: :internal_server_error
      end
    end
  end
end
