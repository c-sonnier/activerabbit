Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/api/*", headers: :any, methods: [:post, :options]
    resource "/replay/*", headers: :any, methods: [:get, :options]
    resource "/rrweb.min.js", headers: :any, methods: [:get, :options]
    resource "/rrweb.min.css", headers: :any, methods: [:get, :options]
  end
end
