# == Schema Information
#
# Table name: qiita
#
#  id               :integer          not null, primary key
#  service_name     :string           not null
#  title            :string           not null
#  url              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  slack_channel_id :integer
#
# Indexes
#
#  index_qiita_on_slack_channel_id  (slack_channel_id)
#
class Qiitum < ApplicationRecord
  belongs_to :slack_channel
  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end
