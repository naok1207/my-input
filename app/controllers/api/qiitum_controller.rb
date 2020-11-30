class Api::QiitumController < ApplicationController
  def callback
    @body = JSON.parse(request.body.read)
    case @body['type']
    when 'url_verification'
      render json: @body
    when 'event_callback'
      if @body['event']['subtype'] == 'message_changed' 
        @body['event']['message']['attachments'].each do |attachment|
          next unless attachment['service_name'] == 'Qiita'
          qiita = Qiitum.create(
            title:  attachment['title'],
            url:    attachment['from_url']
          )
        end
      end
      head :ok
    end
  end
end
