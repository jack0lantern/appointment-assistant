class User < ApplicationRecord
  has_secure_password

  has_one :therapist_profile, class_name: "Therapist", dependent: :destroy
  has_one :client_profile, class_name: "Client", dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :recording_consents, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: %w[client therapist admin] }
end
