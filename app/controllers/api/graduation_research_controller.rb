class Api::GraduationResearchController < ApplicationController
  skip_before_action :verify_authenticity_token
  def callback
    render json: `do.pl '#{params["code"]}' #{params["language"]}`
  end
end
