class TreatmentPlan < ApplicationRecord
  belongs_to :client
  belongs_to :therapist
  belongs_to :current_version, class_name: "TreatmentPlanVersion", optional: true
  has_many :versions, class_name: "TreatmentPlanVersion", dependent: :destroy

  validates :client_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[draft active archived approved] }
end
