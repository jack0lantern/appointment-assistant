class EvaluationRun < ApplicationRecord
  validates :results, presence: true
end
