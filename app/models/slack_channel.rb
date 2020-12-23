# == Schema Information
#
# Table name: slack_channels
#
#  id         :integer          not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  channel_id :string
#
class SlackChannel < ApplicationRecord
  has_many :qiitum

  def self.channel(id)
    channel_id = SlackChannel.find_by(channel_id: id)
    return channel_id if channel_id.present?
    client = Slack::Web::Client.new
    body = client.conversations_list
    body["channels"].each do |channel|
      SlackChannel.create(
        channel_id: channel["id"],
        name: channel["name"]
      )
    end
    SlackChannel.find_by(channel_id: id)
  end
end
