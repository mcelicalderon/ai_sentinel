# frozen_string_literal: true

require 'faraday'

module AiSentinel
  module Actions
    class HttpGet < Base
      Result = Struct.new(:status, :body, :headers, keyword_init: true)

      DEFAULT_TIMEOUT = 30

      def call
        url = interpolate(step.params[:url])
        validate_url!(url)
        headers = step.params.fetch(:headers, {})
        timeout = step.params.fetch(:timeout, DEFAULT_TIMEOUT)

        response = connection(timeout).get(url) do |req|
          headers.each { |k, v| req.headers[k] = interpolate(v.to_s) }
        end

        Result.new(status: response.status, body: response.body, headers: response.headers.to_h)
      end

      private

      def connection(timeout)
        Faraday.new do |f|
          f.options.timeout = timeout
          f.options.open_timeout = timeout
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
