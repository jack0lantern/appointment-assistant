# frozen_string_literal: true

class LivekitTokenService
  class << self
    def server_url
      ENV.fetch("LIVEKIT_URL", "ws://localhost:7880")
    end

    def api_key
      ENV.fetch("LIVEKIT_API_KEY", "devkey")
    end

    def api_secret
      ENV.fetch("LIVEKIT_API_SECRET", "secret")
    end

    # LiveKit access tokens: https://docs.livekit.io/frontends/reference/tokens-grants/
    def issue_token(identity:, room_name:, ttl_seconds: 3600)
      now = Time.now.to_i
      payload = {
        iss: api_key,
        sub: identity,
        nbf: now,
        iat: now,
        exp: now + ttl_seconds,
        video: {
          room: room_name,
          roomJoin: true,
          canPublish: true,
          canSubscribe: true,
          canPublishData: true,
        },
      }
      JWT.encode(payload, api_secret, "HS256")
    end
  end
end
