# frozen_string_literal: true

module Uptime
  class MonitorPolicy < ApplicationPolicy
    def index?
      true
    end

    def show?
      true
    end

    def new?
      user_is_owner?
    end

    def create?
      user_is_owner?
    end

    def edit?
      user_is_owner?
    end

    def update?
      user_is_owner?
    end

    def destroy?
      user_is_owner?
    end

    def pause?
      user_is_owner?
    end

    def resume?
      user_is_owner?
    end

    def check_now?
      user_is_owner?
    end

    private

    def user_is_owner?
      user.owner?
    end
  end
end
