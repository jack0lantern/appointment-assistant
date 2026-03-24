class CreateAllTables < ActiveRecord::Migration[7.2]
  def change
    create_table :users, if_not_exists: true do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :role, limit: 50, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    if column_exists?(:users, :email)
      add_index :users, :email, unique: true, if_not_exists: true
    end

    create_table :therapists, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :license_type, limit: 50, null: false
      t.jsonb :specialties, null: false, default: []
      t.jsonb :preferences, null: false, default: {}
      t.string :slug, limit: 100
      t.timestamps
    end
    add_reference_index :therapists, :user_id, unique: true
    # Legacy DBs may already have therapists without slug; create_table was skipped.
    unless column_exists?(:therapists, :slug)
      add_column :therapists, :slug, :string, limit: 100
    end
    add_index :therapists, :slug, unique: true, where: "slug IS NOT NULL", if_not_exists: true

    create_table :clients, if_not_exists: true do |t|
      t.references :user, foreign_key: true, index: false
      t.references :therapist, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.timestamps
    end
    add_reference_index :clients, :user_id, unique: true
    add_reference_index :clients, :therapist_id

    create_table :sessions, if_not_exists: true do |t|
      t.references :therapist, null: false, foreign_key: true, index: false
      t.references :client, null: false, foreign_key: true, index: false
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
    add_reference_index :sessions, :therapist_id
    add_reference_index :sessions, :client_id

    create_table :transcripts, if_not_exists: true do |t|
      t.references :session, null: false, foreign_key: true, index: false
      t.text :content, null: false
      t.string :source_type, limit: 50, null: false, default: "uploaded"
      t.integer :word_count, null: false, default: 0
      t.jsonb :utterances
      t.jsonb :speaker_map
      t.timestamps
    end
    add_reference_index :transcripts, :session_id, unique: true

    create_table :treatment_plans, if_not_exists: true do |t|
      t.references :client, null: false, foreign_key: true, index: false
      t.references :therapist, null: false, foreign_key: true, index: false
      t.bigint :current_version_id
      t.string :status, limit: 50, null: false, default: "draft"
      t.timestamps
    end
    add_reference_index :treatment_plans, :client_id, unique: true
    add_reference_index :treatment_plans, :therapist_id

    create_table :treatment_plan_versions, if_not_exists: true do |t|
      t.references :treatment_plan, null: false, foreign_key: true, index: false
      t.integer :version_number, null: false
      t.references :session, foreign_key: true, index: false
      t.jsonb :therapist_content
      t.jsonb :client_content
      t.text :change_summary
      t.string :source, limit: 50, null: false, default: "ai_generated"
      t.jsonb :ai_metadata
      t.timestamps
    end
    add_reference_index :treatment_plan_versions, :treatment_plan_id
    add_reference_index :treatment_plan_versions, :session_id

    unless foreign_key_exists?(:treatment_plans, :treatment_plan_versions, column: :current_version_id)
      add_foreign_key :treatment_plans, :treatment_plan_versions, column: :current_version_id
    end

    create_table :safety_flags, if_not_exists: true do |t|
      t.references :session, foreign_key: true, index: false
      t.references :treatment_plan_version, foreign_key: true, index: false
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
      t.references :acknowledged_by, foreign_key: { to_table: :users }, index: false
      t.timestamps
    end
    add_reference_index :safety_flags, :session_id
    add_reference_index :safety_flags, :treatment_plan_version_id
    add_reference_index :safety_flags, :acknowledged_by_id

    create_table :homework_items, if_not_exists: true do |t|
      t.references :treatment_plan_version, null: false, foreign_key: true, index: false
      t.references :client, null: false, foreign_key: true, index: false
      t.text :description, null: false
      t.boolean :completed, null: false, default: false
      t.datetime :completed_at
      t.timestamps
    end
    add_reference_index :homework_items, :treatment_plan_version_id
    add_reference_index :homework_items, :client_id

    create_table :session_summaries, if_not_exists: true do |t|
      t.references :session, null: false, foreign_key: true, index: false
      t.text :therapist_summary
      t.text :client_summary
      t.jsonb :key_themes
      t.timestamps
    end
    add_reference_index :session_summaries, :session_id, unique: true

    create_table :recording_consents, if_not_exists: true do |t|
      t.references :session, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.boolean :consented, null: false
      t.datetime :consented_at
      t.string :ip_address, limit: 45
      t.timestamps
    end
    add_reference_index :recording_consents, :session_id
    add_reference_index :recording_consents, :user_id

    create_table :evaluation_runs, if_not_exists: true do |t|
      t.datetime :run_at, null: false, default: -> { "NOW()" }
      t.jsonb :results, null: false
      t.boolean :overall_pass, null: false, default: false
      t.datetime :created_at, null: false, default: -> { "NOW()" }
    end

    create_table :conversations, if_not_exists: true do |t|
      t.string :uuid, limit: 36, null: false
      t.references :user, null: false, foreign_key: true, index: false
      t.string :context_type, limit: 50, null: false, default: "general"
      t.string :title
      t.string :status, limit: 20, null: false, default: "active"
      t.jsonb :onboarding_progress
      t.timestamps
    end
    if table_exists?(:conversations) && !column_exists?(:conversations, :uuid)
      add_column :conversations, :uuid, :string, limit: 36
      execute "UPDATE conversations SET uuid = gen_random_uuid()::text WHERE uuid IS NULL"
      change_column_null :conversations, :uuid, false
    end
    if column_exists?(:conversations, :uuid)
      add_index :conversations, :uuid, unique: true, if_not_exists: true
    end
    add_reference_index :conversations, :user_id

    create_table :conversation_messages, if_not_exists: true do |t|
      t.references :conversation, null: false, foreign_key: true, index: false
      t.string :role, limit: 20, null: false
      t.text :content, null: false
      t.text :redacted_content
      t.timestamps
    end
    add_reference_index :conversation_messages, :conversation_id
  end

  private

  # With create_table(..., if_not_exists: true), Rails still runs deferred add_index
  # for t.references after CREATE IF NOT EXISTS. If the table already existed without
  # those columns, add_index fails. Disable reference indexes in the block and add
  # them here only when the column exists.
  def add_reference_index(table, column, unique: false)
    return unless table_exists?(table)
    return unless column_exists?(table, column)

    opts = { if_not_exists: true }
    opts[:unique] = true if unique
    add_index table, column, **opts
  end
end
