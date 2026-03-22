class Client < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :therapist
  has_many :sessions, dependent: :destroy
  has_one :treatment_plan, dependent: :destroy
  has_many :homework_items, dependent: :destroy

  validates :user_id, uniqueness: true, allow_nil: true
  validates :name, presence: true
end
