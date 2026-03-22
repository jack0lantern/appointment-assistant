class HomeworkItem < ApplicationRecord
  belongs_to :treatment_plan_version
  belongs_to :client

  validates :description, presence: true
end
