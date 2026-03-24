class TreatmentPlanVersion < ApplicationRecord
  belongs_to :treatment_plan
  belongs_to :session, optional: true
  has_many :safety_flags, dependent: :destroy
  has_many :homework_items, dependent: :destroy

  validates :version_number, presence: true, numericality: { greater_than: 0 }
  validates :source, presence: true, inclusion: { in: %w[ai_generated manual_edit therapist_edit] }
end
