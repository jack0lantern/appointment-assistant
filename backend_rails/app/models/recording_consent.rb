class RecordingConsent < ApplicationRecord
  belongs_to :session
  belongs_to :user
end
