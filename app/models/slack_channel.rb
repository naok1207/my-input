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
end
