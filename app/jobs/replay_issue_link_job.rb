class ReplayIssueLinkJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(replay_id)
    replay = Replay.unscoped.find(replay_id)
    account = replay.account

    ActsAsTenant.with_tenant(account) do
      events = Event.where(
        session_id: replay.session_id,
        project_id: replay.project_id
      )

      events.update_all(replay_id: replay.replay_id)

      if replay.issue_id.nil?
        issue_id = events.where.not(issue_id: nil).pick(:issue_id)
        replay.update!(issue_id: issue_id) if issue_id
      end
    end
  end
end
