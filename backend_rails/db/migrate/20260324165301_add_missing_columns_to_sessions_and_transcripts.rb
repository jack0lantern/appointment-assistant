class AddMissingColumnsToSessionsAndTranscripts < ActiveRecord::Migration[7.2]
  def change
    # Sessions: add live/recording columns missing from prod
    unless column_exists?(:sessions, :session_type)
      add_column :sessions, :session_type, :string, limit: 20, default: "uploaded", null: false
    end
    unless column_exists?(:sessions, :livekit_room_name)
      add_column :sessions, :livekit_room_name, :string
    end
    unless column_exists?(:sessions, :live_session_data)
      add_column :sessions, :live_session_data, :jsonb
    end
    unless column_exists?(:sessions, :recording_status)
      add_column :sessions, :recording_status, :string, limit: 20
    end
    unless column_exists?(:sessions, :recording_storage_path)
      add_column :sessions, :recording_storage_path, :text
    end
    unless column_exists?(:sessions, :recording_egress_id)
      add_column :sessions, :recording_egress_id, :string
    end

    # Transcripts: add structured utterances/speaker_map columns
    unless column_exists?(:transcripts, :utterances)
      add_column :transcripts, :utterances, :jsonb
    end
    unless column_exists?(:transcripts, :speaker_map)
      add_column :transcripts, :speaker_map, :jsonb
    end
  end
end
