# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Actions
    class HttpPost < Base
      Result = Struct.new(:status, :body, :headers, keyword_init: true)

      DEFAULT_TIMEOUT = 30

      def call
        url = interpolate(step.params[:url])
        validate_url!(url)
        payload = build_payload
        headers = step.params.fetch(:headers, {})
        timeout = step.params.fetch(:timeout, DEFAULT_TIMEOUT)

        response = connection(timeout).post(url) do |req|
          req.headers['Content-Type'] = 'application/json'
          headers.each { |k, v| req.headers[k] = interpolate(v.to_s) }
          req.body = payload.is_a?(String) ? payload : JSON.generate(payload)
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

      def build_payload
        payload = step.params[:body] || step.params[:payload] || {}
        return interpolate(payload) if payload.is_a?(String)

        payload.transform_values { |v| interpolate(v.to_s) }
      end
    end
  end
end
