class Session < ApplicationRecord
  belongs_to :therapist
  belongs_to :client
  has_one :transcript, dependent: :destroy
  has_one :session_summary, dependent: :destroy
  has_many :safety_flags, dependent: :destroy
  has_many :recording_consents, dependent: :destroy

  validates :session_number, presence: true, numericality: { greater_than: 0 }
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[scheduled in_progress completed cancelled] }
  validates :session_type, presence: true, inclusion: { in: %w[uploaded live] }
end
