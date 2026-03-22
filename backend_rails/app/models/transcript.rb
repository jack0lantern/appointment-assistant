class Transcript < ApplicationRecord
  belongs_to :session

  validates :session_id, uniqueness: true
  validates :content, presence: true
  validates :source_type, presence: true, inclusion: { in: %w[uploaded live] }
end
