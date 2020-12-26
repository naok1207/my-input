class AddColumnToQiita < ActiveRecord::Migration[5.2]
  def change
    add_column :qiita, :service_name, :string, null: false
  end
end
