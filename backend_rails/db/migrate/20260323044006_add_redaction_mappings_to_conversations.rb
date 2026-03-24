class AddRedactionMappingsToConversations < ActiveRecord::Migration[7.2]
  def change
    return if column_exists?(:conversations, :redaction_mappings)

    add_column :conversations, :redaction_mappings, :jsonb, default: {}
  end
end
