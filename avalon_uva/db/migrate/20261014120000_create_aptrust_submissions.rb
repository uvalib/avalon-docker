# frozen_string_literal: true

class CreateAptrustSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :aptrust_submissions do |t|
      t.string :scope_type, null: false # 'collection' or 'media_object'
      t.string :scope_id, null: false
      t.string :collection_id, null: false
      t.string :status, null: false, default: 'requested'
      t.string :remote_state
      t.string :sid
      t.string :bucket
      t.string :deposit_path
      t.string :requested_by
      t.text :message
      t.text :error_message
      t.datetime :submitted_at
      t.datetime :completed_at
      t.datetime :last_polled_at
      t.timestamps
    end
    add_index :aptrust_submissions, :collection_id
    add_index :aptrust_submissions, :status
    add_index :aptrust_submissions, :sid, unique: true
  end
end
