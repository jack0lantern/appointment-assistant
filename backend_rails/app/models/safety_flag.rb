class SafetyFlag < ApplicationRecord
  belongs_to :session, optional: true
  belongs_to :treatment_plan_version, optional: true
  belongs_to :acknowledged_by, class_name: "User", optional: true

  validates :flag_type, presence: true
  validates :severity, presence: true, inclusion: { in: %w[low medium high critical] }
  validates :description, presence: true
  validates :transcript_excerpt, presence: true
  validates :source, presence: true
  validates :category, presence: true
end
