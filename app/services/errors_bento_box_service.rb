# frozen_string_literal: true

class ErrorsBentoBoxService
  # 20-column grid: square tiles use equal column + row span (1..20).
  MAX_SPAN = 20
  ISSUES_LIMIT = 300

  attr_reader :project_scope, :current_period, :retention_cutoff, :account

  def initialize(project_scope:, period: "all", retention_cutoff: nil, account: nil)
    @project_scope = project_scope
    @current_period = period.presence || "all"
    @retention_cutoff = retention_cutoff
    @account = account
  end

  def call
    issues = fetch_issues
    issues_with_sizes = calculate_box_sizes(issues)
    stats = fetch_summary_stats

    {
      issues: issues,
      issues_with_sizes: issues_with_sizes,
      current_period: current_period,
      total_errors: stats[:total],
      open_errors: stats[:wip],
      resolved_errors: stats[:closed]
    }
  end

  private

  def fetch_issues
    base_scope = project_scope ? project_scope.issues : Issue

    if retention_cutoff
      base_scope = base_scope.where("last_seen_at >= ?", retention_cutoff)
    end

    base_scope = apply_period_filter(base_scope)
    base_scope.order(count: :desc).limit(ISSUES_LIMIT)
  end

  def apply_period_filter(scope)
    case current_period
    when "1h"
      scope.where("last_seen_at > ?", 1.hour.ago)
    when "1d"
      scope.where("last_seen_at > ?", 1.day.ago)
    when "7d"
      scope.where("last_seen_at > ?", 7.days.ago)
    when "30d"
      scope.where("last_seen_at > ?", 30.days.ago)
    when "all"
      scope
    else
      scope
    end
  end

  # Same key => same box size. Different keys => different sizes when possible.
  def count_group_key(count)
    c = count.to_i
    return 0 if c <= 0

    # Small totals: treat exact count as the group (ties share a box size).
    return c if c < 25

    # Larger totals: bucket by ~5% relative bands so "similar" frequencies share a size.
    step = [(c * 0.05).round.clamp(1, c), 1].max
    (c / step) * step
  end

  def calculate_box_sizes(issues)
    return [] if issues.empty?

    span_by_group = assign_spans_to_count_groups(issues)

      issues.map do |issue|
        gkey = count_group_key(issue.count)
        span = (span_by_group[gkey] || 1).clamp(1, MAX_SPAN)

        {
          issue: issue,
          cols: span,
          rows: span,
          size_class: span_to_size_class(span),
          span: span
        }
      end
  end

  def assign_spans_to_count_groups(issues)
    keys = issues.map { |i| count_group_key(i.count) }
    # Highest occurrence groups first → larger boxes; tie-break by key
    distinct_groups = keys.uniq.sort_by { |k| [-max_count_for_group(issues, k), -k] }

    span_by_group = {}
    
    distinct_groups.each_with_index do |group, idx|
      # Distribute sizes from 20x20 down to 1x1 based on rank
      # Top errors get largest boxes, progressively smaller for lower ranks
      if idx == 0
        span = 20  # Largest for top error
      elsif idx == 1
        span = 18
      elsif idx == 2
        span = 16
      elsif idx == 3
        span = 14
      elsif idx == 4
        span = 12
      elsif idx == 5
        span = 11
      elsif idx == 6
        span = 10
      elsif idx == 7
        span = 9
      elsif idx == 8
        span = 8
      elsif idx == 9
        span = 7
      elsif idx == 10
        span = 6
      elsif idx == 11
        span = 5
      elsif idx == 12
        span = 4
      elsif idx == 13
        span = 3
      elsif idx == 14
        span = 2
      else
        # Everything else gets 1x1 for maximum density
        span = 1
      end

      span_by_group[group] = span.clamp(1, MAX_SPAN)
    end

    span_by_group
  end

  def max_count_for_group(issues, group_key)
    issues.select { |i| count_group_key(i.count) == group_key }.map(&:count).map(&:to_i).max || 0
  end

  def span_to_size_class(span)
    case span
    when 10.. then "huge"
    when 8..9 then "xlarge"
    when 6..7 then "large"
    when 4..5 then "medium-large"
    when 3 then "medium"
    when 2 then "medium-small"
    else "tiny"
    end
  end

  def fetch_summary_stats
    stats_cache_key = "errors_stats/#{project_scope&.id || 'global'}/#{account&.id}"
    Rails.cache.fetch(stats_cache_key, expires_in: 2.minutes) do
      issues_base = project_scope ? project_scope.issues : Issue
      if retention_cutoff
        issues_base = issues_base.where("last_seen_at >= ?", retention_cutoff)
      end
      status_counts = issues_base.group(:status).count
      {
        total: status_counts.values.sum,
        wip: status_counts.fetch("wip", 0),
        closed: status_counts.fetch("closed", 0)
      }
    end
  end
end
