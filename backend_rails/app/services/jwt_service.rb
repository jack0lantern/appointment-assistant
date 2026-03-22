class JwtService
  SECRET = ENV.fetch("JWT_SECRET", "dev-secret-key")
  ALGORITHM = "HS256"

  def self.encode(payload, expiration: 24.hours.from_now)
    payload[:exp] = expiration.to_i
    JWT.encode(payload, SECRET, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET, true, algorithm: ALGORITHM)
    HashWithIndifferentAccess.new(decoded.first)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
