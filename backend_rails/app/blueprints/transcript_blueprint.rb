class TranscriptBlueprint < Blueprinter::Base
  identifier :id

  fields :session_id, :content, :source_type, :word_count
end
