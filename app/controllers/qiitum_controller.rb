class QiitumController < ApplicationController
  def index
    @qiitum = Qiitum.all
  end
end
