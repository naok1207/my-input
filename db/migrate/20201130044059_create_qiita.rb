class CreateQiita < ActiveRecord::Migration[5.2]
  def change
    create_table :qiita do |t|
      t.string :title, null: false
      t.string :url, null: false, unique: true

      t.timestamps
    end
  end
end
