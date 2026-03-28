# Parses Sentry-style search queries into filter hashes.
#
# Supported syntax:
#   level:error                     → { level: :error }
#   source:StripeService            → { source: "StripeService" }
#   env:production                  → { environment: "production" }
#   trace:tr_abc123                 → { trace_id: "tr_abc123" }
#   request:req_xyz                 → { request_id: "req_xyz" }
#   customer_id:cus_123             → { params: { "customer_id" => "cus_123" } }
#   free text                       → { message: "free text" }
#
class LogSearchQueryParser
  KNOWN_KEYS = {
    "level" => :level,
    "source" => :source,
    "env" => :environment,
    "environment" => :environment,
    "trace" => :trace_id,
    "trace_id" => :trace_id,
    "request" => :request_id,
    "request_id" => :request_id
  }.freeze

  def self.parse(query)
    return {} if query.blank?

    filters = {}
    free_text_parts = []

    tokens = tokenize(query)
    tokens.each do |token|
      if token.include?(":")
        key, value = token.split(":", 2)
        key = key.strip.downcase
        value = value.strip.delete_prefix('"').delete_suffix('"')

        if KNOWN_KEYS.key?(key)
          filter_key = KNOWN_KEYS[key]
          filters[filter_key] = filter_key == :level ? value.to_sym : value
        else
          # Unknown key:value pairs become param searches
          filters[:params] ||= {}
          filters[:params][key] = value
        end
      else
        free_text_parts << token
      end
    end

    filters[:message] = free_text_parts.join(" ") if free_text_parts.any?
    filters
  end

  def self.tokenize(query)
    tokens = []
    current = +""
    in_quotes = false

    query.each_char do |char|
      case char
      when '"'
        in_quotes = !in_quotes
        current << char
      when " "
        if in_quotes
          current << char
        else
          tokens << current unless current.empty?
          current = +""
        end
      else
        current << char
      end
    end

    tokens << current unless current.empty?
    tokens
  end
end
