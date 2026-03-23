# frozen_string_literal: true

class UptimePingJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 1

  LOCK_TTL_BUFFER = 10
  MAX_REDIRECTS = 5
  CHECK_REGION = ENV.fetch("UPTIME_CHECK_REGION", "US West (Los Angeles)").freeze

  def perform(monitor_id)
    monitor = ActsAsTenant.without_tenant { UptimeMonitor.find_by(id: monitor_id) }
    return unless monitor
    return if monitor.paused?

    lock_key = "uptime_ping:#{monitor.id}"
    lock_ttl = monitor.timeout_seconds + LOCK_TTL_BUFFER

    lock_acquired = Sidekiq.redis { |r| r.set(lock_key, "1", ex: lock_ttl, nx: true) }
    return unless lock_acquired

    begin
      result = perform_http_check(monitor)

      ActsAsTenant.with_tenant(monitor.account) do
        save_check_result(monitor, result)
        update_monitor_status(monitor, result)
      end
    ensure
      Sidekiq.redis { |r| r.del(lock_key) }
    end
  end

  private

  def perform_http_check(monitor)
    uri = URI.parse(monitor.url)
    result = { region: CHECK_REGION }

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      dns_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Addrinfo.getaddrinfo(uri.host, uri.port, nil, :STREAM)
      result[:dns_time_ms] = ms_since(dns_start)

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = [monitor.timeout_seconds, 10].min
      http.read_timeout = monitor.timeout_seconds

      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      connect_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http.start do |conn|
        result[:connect_time_ms] = ms_since(connect_start)

        if conn.use_ssl? && conn.peer_cert
          result[:ssl_expiry] = conn.peer_cert.not_after
          result[:tls_time_ms] = ms_since(connect_start) - (result[:connect_time_ms] || 0)
        end

        request = build_request(monitor, uri)
        ttfb_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = conn.request(request)
        result[:ttfb_ms] = ms_since(ttfb_start)

        redirect_count = 0
        while response.is_a?(Net::HTTPRedirection) && redirect_count < MAX_REDIRECTS
          redirect_count += 1
          redirect_uri = URI.parse(response['location'])
          redirect_uri = URI.join(uri, redirect_uri) unless redirect_uri.host
          request = Net::HTTP::Get.new(redirect_uri)
          response = conn.request(request)
        end

        result[:status_code] = response.code.to_i
        result[:success] = result[:status_code] == monitor.expected_status_code
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      result[:success] = false
      result[:error_message] = "Timeout: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      result[:success] = false
      result[:error_message] = "Connection error: #{e.message}"
    rescue OpenSSL::SSL::SSLError => e
      result[:success] = false
      result[:error_message] = "SSL error: #{e.message}"
    rescue StandardError => e
      result[:success] = false
      result[:error_message] = "Error: #{e.class} - #{e.message}"
    end

    result[:response_time_ms] = ms_since(start_time)
    result
  end

  def build_request(monitor, uri)
    case monitor.http_method
    when "HEAD"
      req = Net::HTTP::Head.new(uri)
    when "POST"
      req = Net::HTTP::Post.new(uri)
      req.body = monitor.body if monitor.body.present?
      req.content_type = "application/json"
    else
      req = Net::HTTP::Get.new(uri)
    end

    if monitor.headers.present?
      monitor.headers.each { |k, v| req[k] = v }
    end

    req["User-Agent"] = "ActiveRabbit Uptime/1.0"
    req
  end

  def save_check_result(monitor, result)
    UptimeCheck.create!(
      uptime_monitor: monitor,
      account_id: monitor.account_id,
      status_code: result[:status_code],
      response_time_ms: result[:response_time_ms]&.round,
      success: result[:success] || false,
      error_message: result[:error_message],
      region: result[:region],
      dns_time_ms: result[:dns_time_ms]&.round,
      connect_time_ms: result[:connect_time_ms]&.round,
      tls_time_ms: result[:tls_time_ms]&.round,
      ttfb_ms: result[:ttfb_ms]&.round
    )
  end

  def update_monitor_status(monitor, result)
    previous_status = monitor.status

    if result[:success]
      new_status = "up"
      monitor.update!(
        status: new_status,
        last_checked_at: Time.current,
        last_status_code: result[:status_code],
        last_response_time_ms: result[:response_time_ms]&.round,
        consecutive_failures: 0,
        ssl_expiry: result[:ssl_expiry] || monitor.ssl_expiry
      )
    else
      new_failures = monitor.consecutive_failures + 1
      new_status = new_failures >= monitor.alert_threshold ? "down" : monitor.status
      new_status = "down" if new_failures >= monitor.alert_threshold

      monitor.update!(
        status: new_status,
        last_checked_at: Time.current,
        last_status_code: result[:status_code],
        last_response_time_ms: result[:response_time_ms]&.round,
        consecutive_failures: new_failures,
        ssl_expiry: result[:ssl_expiry] || monitor.ssl_expiry
      )
    end

    if previous_status != "pending" && previous_status != new_status
      if new_status == "down" && previous_status != "down"
        UptimeAlertJob.perform_async(monitor.id, "down", { consecutive_failures: monitor.consecutive_failures })
      elsif new_status == "up" && previous_status == "down"
        UptimeAlertJob.perform_async(monitor.id, "up", { previous_status: previous_status })
      end
    end
  end

  def ms_since(start)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
  end
end
