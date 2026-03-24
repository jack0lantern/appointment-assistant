Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    raw = ENV.fetch("CORS_ORIGINS", "http://localhost:5173")
    # Browser Origin is always a full URL (e.g. https://app.up.railway.app). Allow bare hostnames in env.
    origins_list = raw.split(",").map(&:strip).reject(&:empty?).map do |origin|
      origin.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:\/\//) ? origin : "https://#{origin}"
    end
    origins(*origins_list)
    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization]
  end
end
