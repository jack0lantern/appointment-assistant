class CreateAllTables < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :role, limit: 50, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :therapists do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :license_type, limit: 50, null: false
      t.jsonb :specialties, null: false, default: []
      t.jsonb :preferences, null: false, default: {}
      t.string :slug, limit: 100
      t.timestamps
    end
    add_index :therapists, :slug, unique: true, where: "slug IS NOT NULL"

    create_table :clients do |t|
      t.references :user, foreign_key: true, index: { unique: true }
      t.references :therapist, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :sessions do |t|
      t.references :therapist, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.datetime :session_date
      t.integer :session_number, null: false, default: 1
      t.integer :duration_minutes, null: false, default: 50
      t.string :status, limit: 50, null: false, default: "completed"
      t.string :session_type, limit: 20, null: false, default: "uploaded"
      t.string :livekit_room_name
      t.jsonb :live_session_data
      t.string :recording_status, limit: 20
      t.text :recording_storage_path
      t.string :recording_egress_id
      t.timestamps
    end

    create_table :transcripts do |t|
      t.references :session, null: false, foreign_key: true, index: { unique: true }
      t.text :content, null: false
      t.string :source_type, limit: 50, null: false, default: "uploaded"
      t.integer :word_count, null: false, default: 0
      t.jsonb :utterances
      t.jsonb :speaker_map
      t.timestamps
    end

    create_table :treatment_plans do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.references :therapist, null: false, foreign_key: true
      t.bigint :current_version_id
      t.string :status, limit: 50, null: false, default: "draft"
      t.timestamps
    end

    create_table :treatment_plan_versions do |t|
      t.references :treatment_plan, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.references :session, foreign_key: true
      t.jsonb :therapist_content
      t.jsonb :client_content
      t.text :change_summary
      t.string :source, limit: 50, null: false, default: "ai_generated"
      t.jsonb :ai_metadata
      t.timestamps
    end

    add_foreign_key :treatment_plans, :treatment_plan_versions, column: :current_version_id

    create_table :safety_flags do |t|
      t.references :session, foreign_key: true
      t.references :treatment_plan_version, foreign_key: true
      t.string :flag_type, limit: 50, null: false
      t.string :severity, limit: 50, null: false
      t.text :description, null: false
      t.text :transcript_excerpt, null: false
      t.integer :line_start
      t.integer :line_end
      t.string :source, limit: 50, null: false, default: "regex"
      t.string :category, limit: 50, null: false, default: "safety_risk"
      t.boolean :acknowledged, null: false, default: false
      t.datetime :acknowledged_at
      t.references :acknowledged_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :homework_items do |t|
      t.references :treatment_plan_version, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.text :description, null: false
      t.boolean :completed, null: false, default: false
      t.datetime :completed_at
      t.timestamps
    end

    create_table :session_summaries do |t|
      t.references :session, null: false, foreign_key: true, index: { unique: true }
      t.text :therapist_summary
      t.text :client_summary
      t.jsonb :key_themes
      t.timestamps
    end

    create_table :recording_consents do |t|
      t.references :session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :consented, null: false
      t.datetime :consented_at
      t.string :ip_address, limit: 45
      t.timestamps
    end

    create_table :evaluation_runs do |t|
      t.datetime :run_at, null: false, default: -> { "NOW()" }
      t.jsonb :results, null: false
      t.boolean :overall_pass, null: false, default: false
      t.datetime :created_at, null: false, default: -> { "NOW()" }
    end

    create_table :conversations do |t|
      t.string :uuid, limit: 36, null: false
      t.references :user, null: false, foreign_key: true
      t.string :context_type, limit: 50, null: false, default: "general"
      t.string :title
      t.string :status, limit: 20, null: false, default: "active"
      t.jsonb :onboarding_progress
      t.timestamps
    end
    add_index :conversations, :uuid, unique: true

    create_table :conversation_messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, limit: 20, null: false
      t.text :content, null: false
      t.text :redacted_content
      t.timestamps
    end
  end
end
