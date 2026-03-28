class CliController < ApplicationController
  skip_before_action :authenticate_user!
  layout "public"

  # GET /cli — landing page
  def show
  end

  # GET /cli/install.sh — installer script
  def install_script
    send_file Rails.root.join("script/cli/install.sh"),
      type: "text/plain",
      disposition: "inline"
  end

  # GET /cli/activerabbit — CLI script download
  def cli_script
    send_file Rails.root.join("script/cli/activerabbit"),
      type: "text/plain",
      disposition: "inline"
  end
end
