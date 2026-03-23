#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick script to seed errors for a project
# Usage: rails runner script/seed_errors.rb acme-web [max_per_type]
# Each of the 30 error types gets a random count from 1 to max_per_type (default 100).

require_relative '../config/environment'

slug = ARGV[0] || "acme-web"
max_per_type = (ARGV[1] || 100).to_i

# Sample error payloads - load from rake task namespace
load File.expand_path('../lib/tasks/seed_errors.rake', __dir__)
SAMPLE_ERRORS = SeedErrors::SAMPLE_ERRORS

# Find project without tenant scope
project = ActsAsTenant.without_tenant { Project.find_by(slug: slug) }
unless project
  puts "Project with slug '#{slug}' not found."
  puts "Available projects: #{ActsAsTenant.without_tenant { Project.pluck(:slug).join(', ') }}"
  exit 1
end

# Set tenant for Event/Issue creation
ActsAsTenant.current_tenant = project.account
begin
  period_start = 30.days.ago
  period_end = Time.current
  created = 0

  puts "Seeding #{SAMPLE_ERRORS.size} error types with random counts (1–#{max_per_type} events per type)..."
  puts "Spread over: #{period_start.to_date} .. #{period_end.to_date}"
  puts

  SAMPLE_ERRORS.each_with_index do |scenario, _idx|
    count_for_type = rand(1..max_per_type)
    count_for_type.times do
      occurred_at = Time.at(period_start + (period_end - period_start) * rand)

      payload = scenario.merge(
        occurred_at: occurred_at,
        request_id: SecureRandom.uuid,
        user_id: "user-#{rand(1..100)}",
        context: { "ruby_version" => "3.4.8", "rails_version" => "8.0.2.1" }
      )

      Event.ingest_error(project: project, payload: payload)
      created += 1
      print "." if (created % 50).zero?
    end
  end

  puts
  puts "Created #{created} events (#{project.issues.reload.count} issues for this project)."
  puts "View errors: http://localhost:3003/#{slug}/errors/all?period=30d"
ensure
  ActsAsTenant.current_tenant = nil
end
