class CreateSlackChannels < ActiveRecord::Migration[5.2]
  def change
    create_table :slack_channels do |t|
      t.string :channel_id
      t.string :name

      t.timestamps
    end
  end
end
