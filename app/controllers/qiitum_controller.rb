class QiitumController < ApplicationController
  def index
    @channels = SlackChannel.all
    @qiitum = if params[:channel_id].present? && params[:channel_id] != ''
                @channel_id = params[:channel_id]
                Qiitum.where(slack_channel_id: params[:channel_id])
              else
                Qiitum.all
              end
  end
end
