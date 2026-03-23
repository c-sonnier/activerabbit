require 'rails_helper'

RSpec.describe Issue, type: :model do
  let(:project) { create(:project) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:fingerprint) }
    it { is_expected.to validate_presence_of(:exception_class) }
    it { is_expected.to validate_presence_of(:top_frame) }
    it { is_expected.to validate_presence_of(:controller_action) }
  end

  describe '.find_or_create_by_fingerprint' do
    it 'creates a new issue and increments counts properly' do
      issue = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: "/app/controllers/home_controller.rb:10:in `index'",
        controller_action: 'HomeController#index',
        sample_message: 'boom'
      )
      expect(issue).to be_persisted
      expect(issue.count).to eq(1)

      same = Issue.find_or_create_by_fingerprint(
        project: project,
        exception_class: 'RuntimeError',
        top_frame: "/app/controllers/home_controller.rb:32:in `index'",
        controller_action: 'HomeController#index',
        sample_message: 'boom again'
      )
      expect(same.id).to eq(issue.id)
      expect(same.count).to eq(2)
    end
  end

  describe '#status transitions' do
    it 'sets wip/close/reopen' do
      issue = create(:issue, project: project)
      issue.mark_wip!
      expect(issue.status).to eq('wip')
      issue.close!
      expect(issue.status).to eq('closed')
      issue.reopen!
      expect(issue.status).to eq('open')
    end
  end

  describe 'auto_fix_status validation' do
    it 'accepts valid auto_fix_status values' do
      issue = create(:issue, project: project)
      Issue::AUTO_FIX_STATUSES.each do |status|
        issue.update_columns(auto_fix_status: status)
        issue.reload
        expect(issue.auto_fix_status).to eq(status)
      end
    end

    it 'allows nil auto_fix_status' do
      issue = build(:issue, project: project)
      issue.auto_fix_status = nil
      expect(issue).to be_valid
    end

    it 'rejects invalid auto_fix_status' do
      issue = build(:issue, project: project)
      issue.auto_fix_status = "invalid_status"
      expect(issue).not_to be_valid
    end
  end

  describe '#auto_fix_in_progress?' do
    let(:issue) { create(:issue, project: project) }

    it 'returns true for creating_pr' do
      issue.update_columns(auto_fix_status: "creating_pr")
      expect(issue.auto_fix_in_progress?).to be true
    end

    it 'returns true for pr_created' do
      issue.update_columns(auto_fix_status: "pr_created")
      expect(issue.auto_fix_in_progress?).to be true
    end

    it 'returns true for ci_pending' do
      issue.update_columns(auto_fix_status: "ci_pending")
      expect(issue.auto_fix_in_progress?).to be true
    end

    it 'returns false for merged' do
      issue.update_columns(auto_fix_status: "merged")
      expect(issue.auto_fix_in_progress?).to be false
    end

    it 'returns false for failed' do
      issue.update_columns(auto_fix_status: "failed")
      expect(issue.auto_fix_in_progress?).to be false
    end

    it 'returns false for nil' do
      expect(issue.auto_fix_in_progress?).to be false
    end
  end

  describe '#auto_fix_completed?' do
    let(:issue) { create(:issue, project: project) }

    it 'returns true only for merged' do
      issue.update_columns(auto_fix_status: "merged")
      expect(issue.auto_fix_completed?).to be true
    end

    it 'returns false for other statuses' do
      %w[pr_created failed ci_failed].each do |status|
        issue.update_columns(auto_fix_status: status)
        expect(issue.auto_fix_completed?).to be false
      end
    end
  end

  describe '#auto_fix_failed?' do
    let(:issue) { create(:issue, project: project) }

    it 'returns true for failure statuses' do
      %w[failed ci_failed ci_timeout merge_failed monitor_error].each do |status|
        issue.update_columns(auto_fix_status: status)
        expect(issue.auto_fix_failed?).to be true
      end
    end

    it 'returns false for success statuses' do
      %w[pr_created merged ci_pending].each do |status|
        issue.update_columns(auto_fix_status: status)
        expect(issue.auto_fix_failed?).to be false
      end
    end
  end

  describe '#auto_fix_eligible?' do
    let(:issue) { create(:issue, project: project, ai_summary: "## Fix\ndo this") }

    it 'returns true when open, has summary, no auto_fix_status' do
      expect(issue.auto_fix_eligible?).to be true
    end

    it 'returns false when auto_fix_status is set' do
      issue.update_columns(auto_fix_status: "pr_created")
      expect(issue.auto_fix_eligible?).to be false
    end

    it 'returns false when closed' do
      issue.close!
      expect(issue.auto_fix_eligible?).to be false
    end

    it 'returns false without ai_summary' do
      issue.update_columns(ai_summary: nil)
      expect(issue.auto_fix_eligible?).to be false
    end
  end
end
