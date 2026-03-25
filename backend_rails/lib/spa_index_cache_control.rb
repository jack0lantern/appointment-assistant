# frozen_string_literal: true

# When +public_file_server.headers+ applies long-lived caching to files under +public/+,
# +ActionDispatch::Static+ serves +index.html+ for GET +/+ with those headers. The SPA
# shell must revalidate so clients pick up new deployments. Inserted immediately before
# +ActionDispatch::Static+ so we can rewrite +Cache-Control+ on that response only.
class SpaIndexCacheControl
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    if apply?(env, status, headers)
      headers = headers.merge("Cache-Control" => "no-cache, must-revalidate")
    end
    [status, headers, body]
  end

  private

  def apply?(env, status, headers)
    return false unless env["REQUEST_METHOD"] == "GET"
    return false unless status == 200

    path = env["PATH_INFO"].to_s
    return false unless path == "/" || path == "/index.html"
    return false unless html?(headers)

    true
  end

  def html?(headers)
    type = headers["Content-Type"] || headers["content-type"]
    return false if type.nil? || type.empty?

    type.split(";").first.to_s.strip.downcase == "text/html"
  end
end
