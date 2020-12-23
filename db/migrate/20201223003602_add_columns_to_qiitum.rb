class AddColumnsToQiitum < ActiveRecord::Migration[5.2]
  def change
    add_reference :qiita, :slack_channel, foreign_key: true
  end
end
