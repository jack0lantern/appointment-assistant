class Therapist < ApplicationRecord
  belongs_to :user
  has_many :clients, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :treatment_plans, dependent: :destroy

  validates :user_id, uniqueness: true
  validates :license_type, presence: true
end
