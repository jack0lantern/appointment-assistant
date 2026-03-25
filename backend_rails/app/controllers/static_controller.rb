# Serves the SPA index.html for client-side routing (e.g. /onboard/:slug).
# Used when frontend is built and copied into public/ (Docker deployment).
class StaticController < ActionController::API
  def index
    index_path = Rails.public_path.join("index.html")
    if index_path.exist?
      send_file index_path,
        type: "text/html",
        disposition: "inline",
        headers: { "Cache-Control" => "no-cache, must-revalidate" }
    else
      head :not_found
    end
  end
end
