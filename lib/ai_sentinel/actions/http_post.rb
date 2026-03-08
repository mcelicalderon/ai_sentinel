# frozen_string_literal: true

require 'faraday'
require 'json'

module AiSentinel
  module Actions
    class HttpPost < Base
      Result = Struct.new(:status, :body, :headers, keyword_init: true)

      def call
        url = interpolate(step.params[:url])
        payload = build_payload
        headers = step.params.fetch(:headers, {})

        response = Faraday.post(url) do |req|
          req.headers['Content-Type'] = 'application/json'
          headers.each { |k, v| req.headers[k] = interpolate(v.to_s) }
          req.body = payload.is_a?(String) ? payload : JSON.generate(payload)
        end

        Result.new(status: response.status, body: response.body, headers: response.headers.to_h)
      end

      private

      def build_payload
        payload = step.params[:body] || step.params[:payload] || {}
        return interpolate(payload) if payload.is_a?(String)

        payload.transform_values { |v| interpolate(v.to_s) }
      end
    end
  end
end
