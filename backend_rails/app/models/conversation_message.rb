class ConversationMessage < ApplicationRecord
  belongs_to :conversation

  validates :role, presence: true, inclusion: { in: %w[user assistant system tool] }
  validates :content, presence: true
end
