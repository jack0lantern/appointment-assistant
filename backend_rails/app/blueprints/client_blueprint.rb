class ClientBlueprint < Blueprinter::Base
  identifier :id

  fields :user_id, :therapist_id, :name

  # Counts completed sessions only — same rule as GET /api/my/sessions and client detail session list.
  field :session_count do |client, options|
    stats_by_client = options[:session_stats]
    if stats_by_client
      stats_by_client[client.id]&.fetch(:session_count) || 0
    else
      client.sessions.where(status: "completed").count
    end
  end

  field :last_session_date do |client, options|
    raw = if options[:session_stats]
      options[:session_stats][client.id]&.fetch(:last_session_date, nil)
    else
      client.sessions.where(status: "completed").maximum(:session_date)
    end
    case raw
    when nil then nil
    when String then raw
    else raw.iso8601
    end
  end
end
