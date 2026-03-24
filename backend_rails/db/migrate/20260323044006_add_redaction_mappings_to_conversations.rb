class AddRedactionMappingsToConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :conversations, :redaction_mappings, :jsonb, default: {}
  end
end
