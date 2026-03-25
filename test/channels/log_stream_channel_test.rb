require "test_helper"

class LogStreamChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:owner)
    @project = projects(:default)
    stub_connection current_user: @user
  end

  test "subscribes to project stream" do
    subscribe(project_id: @project.id)
    assert subscription.confirmed?
    assert_has_stream "log_stream:#{@project.id}"
  end

  test "rejects subscription without valid project" do
    subscribe(project_id: -1)
    assert subscription.rejected?
  end
end
