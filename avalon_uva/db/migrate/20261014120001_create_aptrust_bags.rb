# frozen_string_literal: true

class CreateAptrustBags < ActiveRecord::Migration[8.0]
  def change
    create_table :aptrust_bags do |t|
      t.references :aptrust_submission, null: false, foreign_key: true
      t.string :media_object_id, null: false
      t.string :bag_name, null: false
      t.string :status, null: false, default: 'pending'
      t.string :remote_state
      t.integer :file_count
      t.bigint :byte_size
      t.datetime :source_modified_at
      t.text :error_message
      t.timestamps
    end
    add_index :aptrust_bags, :media_object_id
    add_index :aptrust_bags, [:aptrust_submission_id, :bag_name], unique: true
  end
end
