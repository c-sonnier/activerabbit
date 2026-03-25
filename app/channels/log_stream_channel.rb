# frozen_string_literal: true

class LogStreamChannel < ApplicationCable::Channel
  def subscribed
    project = find_project
    if project
      stream_from "log_stream:#{project.id}"
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end

  private

  def find_project
    account = current_user&.account
    return nil unless account

    project_id = params[:project_id]
    account.projects.find_by(id: project_id)
  end
end
