# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_03_22_205229) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "clients", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "therapist_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["therapist_id"], name: "index_clients_on_therapist_id"
    t.index ["user_id"], name: "index_clients_on_user_id", unique: true
  end

  create_table "conversation_messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "role", limit: 20, null: false
    t.text "content", null: false
    t.text "redacted_content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_conversation_messages_on_conversation_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "uuid", limit: 36, null: false
    t.bigint "user_id", null: false
    t.string "context_type", limit: 50, default: "general", null: false
    t.string "title"
    t.string "status", limit: 20, default: "active", null: false
    t.jsonb "onboarding_progress"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_conversations_on_user_id"
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
  end

  create_table "evaluation_runs", force: :cascade do |t|
    t.datetime "run_at", default: -> { "now()" }, null: false
    t.jsonb "results", null: false
    t.boolean "overall_pass", default: false, null: false
    t.datetime "created_at", default: -> { "now()" }, null: false
  end

  create_table "homework_items", force: :cascade do |t|
    t.bigint "treatment_plan_version_id", null: false
    t.bigint "client_id", null: false
    t.text "description", null: false
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_homework_items_on_client_id"
    t.index ["treatment_plan_version_id"], name: "index_homework_items_on_treatment_plan_version_id"
  end

  create_table "recording_consents", force: :cascade do |t|
    t.bigint "session_id", null: false
    t.bigint "user_id", null: false
    t.boolean "consented", null: false
    t.datetime "consented_at"
    t.string "ip_address", limit: 45
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_recording_consents_on_session_id"
    t.index ["user_id"], name: "index_recording_consents_on_user_id"
  end

  create_table "safety_flags", force: :cascade do |t|
    t.bigint "session_id"
    t.bigint "treatment_plan_version_id"
    t.string "flag_type", limit: 50, null: false
    t.string "severity", limit: 50, null: false
    t.text "description", null: false
    t.text "transcript_excerpt", null: false
    t.integer "line_start"
    t.integer "line_end"
    t.string "source", limit: 50, default: "regex", null: false
    t.string "category", limit: 50, default: "safety_risk", null: false
    t.boolean "acknowledged", default: false, null: false
    t.datetime "acknowledged_at"
    t.bigint "acknowledged_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_by_id"], name: "index_safety_flags_on_acknowledged_by_id"
    t.index ["session_id"], name: "index_safety_flags_on_session_id"
    t.index ["treatment_plan_version_id"], name: "index_safety_flags_on_treatment_plan_version_id"
  end

  create_table "session_summaries", force: :cascade do |t|
    t.bigint "session_id", null: false
    t.text "therapist_summary"
    t.text "client_summary"
    t.jsonb "key_themes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_session_summaries_on_session_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "therapist_id", null: false
    t.bigint "client_id", null: false
    t.datetime "session_date"
    t.integer "session_number", default: 1, null: false
    t.integer "duration_minutes", default: 50, null: false
    t.string "status", limit: 50, default: "completed", null: false
    t.string "session_type", limit: 20, default: "uploaded", null: false
    t.string "livekit_room_name"
    t.jsonb "live_session_data"
    t.string "recording_status", limit: 20
    t.text "recording_storage_path"
    t.string "recording_egress_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_sessions_on_client_id"
    t.index ["therapist_id"], name: "index_sessions_on_therapist_id"
  end

  create_table "therapists", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "license_type", limit: 50, null: false
    t.jsonb "specialties", default: [], null: false
    t.jsonb "preferences", default: {}, null: false
    t.string "slug", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_therapists_on_slug", unique: true, where: "(slug IS NOT NULL)"
    t.index ["user_id"], name: "index_therapists_on_user_id", unique: true
  end

  create_table "transcripts", force: :cascade do |t|
    t.bigint "session_id", null: false
    t.text "content", null: false
    t.string "source_type", limit: 50, default: "uploaded", null: false
    t.integer "word_count", default: 0, null: false
    t.jsonb "utterances"
    t.jsonb "speaker_map"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_transcripts_on_session_id", unique: true
  end

  create_table "treatment_plan_versions", force: :cascade do |t|
    t.bigint "treatment_plan_id", null: false
    t.integer "version_number", null: false
    t.bigint "session_id"
    t.jsonb "therapist_content"
    t.jsonb "client_content"
    t.text "change_summary"
    t.string "source", limit: 50, default: "ai_generated", null: false
    t.jsonb "ai_metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_treatment_plan_versions_on_session_id"
    t.index ["treatment_plan_id"], name: "index_treatment_plan_versions_on_treatment_plan_id"
  end

  create_table "treatment_plans", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "therapist_id", null: false
    t.bigint "current_version_id"
    t.string "status", limit: 50, default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_treatment_plans_on_client_id", unique: true
    t.index ["therapist_id"], name: "index_treatment_plans_on_therapist_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "role", limit: 50, null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "clients", "therapists"
  add_foreign_key "clients", "users"
  add_foreign_key "conversation_messages", "conversations"
  add_foreign_key "conversations", "users"
  add_foreign_key "homework_items", "clients"
  add_foreign_key "homework_items", "treatment_plan_versions"
  add_foreign_key "recording_consents", "sessions"
  add_foreign_key "recording_consents", "users"
  add_foreign_key "safety_flags", "sessions"
  add_foreign_key "safety_flags", "treatment_plan_versions"
  add_foreign_key "safety_flags", "users", column: "acknowledged_by_id"
  add_foreign_key "session_summaries", "sessions"
  add_foreign_key "sessions", "clients"
  add_foreign_key "sessions", "therapists"
  add_foreign_key "therapists", "users"
  add_foreign_key "transcripts", "sessions"
  add_foreign_key "treatment_plan_versions", "sessions"
  add_foreign_key "treatment_plan_versions", "treatment_plans"
  add_foreign_key "treatment_plans", "clients"
  add_foreign_key "treatment_plans", "therapists"
  add_foreign_key "treatment_plans", "treatment_plan_versions", column: "current_version_id"
end
