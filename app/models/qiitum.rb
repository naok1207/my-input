# == Schema Information
#
# Table name: qiita
#
#  id         :integer          not null, primary key
#  title      :string           not null
#  url        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Qiitum < ApplicationRecord
  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end