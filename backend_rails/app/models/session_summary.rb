class SessionSummary < ApplicationRecord
  belongs_to :session

  validates :session_id, uniqueness: true
end
