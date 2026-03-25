require "rails_helper"

RSpec.describe "SPA shell vs /assets", type: :request do
  around do |example|
    FileUtils.mkdir_p(Rails.public_path)
    index_path = Rails.public_path.join("index.html")
    File.write(index_path, "<!doctype html><html><body>spa-shell</body></html>")
    example.run
  ensure
    FileUtils.rm_f(index_path)
  end

  it "returns 404 for a missing file under /assets (does not serve index.html)" do
    get "/assets/nonexistent-chunk-67df68.js"
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("spa-shell")
  end

  it "serves the SPA index at / with cache revalidation headers" do
    get "/"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("spa-shell")
    cc = response.headers["Cache-Control"]
    expect(cc).to be_present
    expect(cc).to match(/no-cache|must-revalidate|max-age=0/)
  end
end
