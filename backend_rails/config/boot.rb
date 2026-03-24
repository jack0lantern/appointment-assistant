ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# SQLAlchemy/async drivers use schemes like postgresql+asyncpg:// — Active Record only
# understands postgresql:// or postgres://. Normalize before database.yml is evaluated.
if (db_url = ENV["DATABASE_URL"])
  ENV["DATABASE_URL"] = db_url.sub(/\A(postgresql|postgres)\+asyncpg:/i, '\1:')
end

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
