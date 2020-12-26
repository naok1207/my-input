class Api::QiitumController < ApplicationController
  def callback
    @body = JSON.parse(request.body.read)
    case @body['type']
    when 'url_verification'
      render json: @body
    when 'event_callback'
      if @body['event']['subtype'] == 'message_changed'
        @channel = SlackChannel.channel(@body['event']['channel'])
        @body['event']['message']['attachments'].each do |attachment|
          next unless attachment['service_name'].present?
          qiita = @channel.qiitum.create(
            title:  attachment['title'],
            url:    attachment['from_url'],
            service_name: attachment['service_name']
          )
        end
      end
      head :ok
    end
  end
end
