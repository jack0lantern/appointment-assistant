# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatHistoryTruncator do
  describe ".truncate" do
    it "returns empty array for nil or empty input" do
      expect(described_class.truncate(nil)).to eq([])
      expect(described_class.truncate([])).to eq([])
    end

    it "returns messages unchanged when under both limits" do
      messages = [
        { role: "user", content: "Hi" },
        { role: "assistant", content: "Hello!" }
      ]
      expect(described_class.truncate(messages, max_messages: 10, max_content_chars: 10_000)).to eq(
        [
          { role: "user", content: "Hi" },
          { role: "assistant", content: "Hello!" }
        ]
      )
    end

    it "keeps the most recent messages when over max_messages" do
      old = (1..50).map { |i| { role: "user", content: "m#{i}" } }
      result = described_class.truncate(old, max_messages: 5, max_content_chars: 1_000_000)
      expect(result.length).to eq(5)
      expect(result.map { |m| m[:content] }).to eq(%w[m46 m47 m48 m49 m50])
    end

    it "drops oldest messages when total content exceeds max_content_chars" do
      messages = [
        { role: "user", content: "a" * 60 },
        { role: "assistant", content: "b" * 60 },
        { role: "user", content: "tail" }
      ]
      result = described_class.truncate(
        messages,
        max_messages: 10,
        max_content_chars: 100
      )
      expect(result.map { |m| m[:content].length }.sum).to be <= 100
      expect(result.last[:content]).to eq("tail")
    end

    it "strips leading assistant messages after truncation so history starts with user when possible" do
      messages = [
        { role: "user", content: "old" },
        { role: "assistant", content: "old reply" },
        { role: "assistant", content: "orphaned" },
        { role: "user", content: "recent" }
      ]
      result = described_class.truncate(
        messages,
        max_messages: 3,
        max_content_chars: 10_000
      )
      expect(result.first[:role]).to eq("user")
      expect(result.first[:content]).to eq("recent")
    end

    it "accepts string keys for role and content" do
      messages = [{ "role" => "user", "content" => "x" }]
      result = described_class.truncate(messages, max_messages: 5, max_content_chars: 100)
      expect(result).to eq([{ role: "user", content: "x" }])
    end

    it "truncates a single oversized message to fit max_content_chars" do
      messages = [{ role: "user", content: "z" * 200 }]
      result = described_class.truncate(
        messages,
        max_messages: 10,
        max_content_chars: 50
      )
      expect(result.length).to eq(1)
      expect(result.first[:content].length).to be <= 50
      expect(result.first[:content]).to end_with(described_class::TRUNCATION_SUFFIX)
    end
  end
end
