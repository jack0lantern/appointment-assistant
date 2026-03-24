Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    raw = ENV.fetch("CORS_ORIGINS", "http://localhost:5173")
    # Browser Origin is always a full URL (e.g. https://app.up.railway.app). Allow bare hostnames in env.
    origins_list = raw.split(",").map(&:strip).reject(&:empty?).map do |origin|
      origin.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:\/\//) ? origin : "https://#{origin}"
    end
    # Vite picks the next free port when 5173 is taken (5174, 5175, …). Without this, the browser
    # blocks API calls and axios surfaces ERR_NETWORK even though Rails is up.
    dev_localhost = /\Ahttps?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\z/
    if Rails.env.development?
      origins(*origins_list, dev_localhost)
    else
      origins(*origins_list)
    end
    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization]
  end
end
