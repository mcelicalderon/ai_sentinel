# frozen_string_literal: true

require 'faraday'

module AiSentinel
  module Actions
    class HttpGet < Base
      Result = Struct.new(:status, :body, :headers, keyword_init: true)

      def call
        url = interpolate(step.params[:url])
        headers = step.params.fetch(:headers, {})

        response = Faraday.get(url) do |req|
          headers.each { |k, v| req.headers[k] = interpolate(v.to_s) }
        end

        Result.new(status: response.status, body: response.body, headers: response.headers.to_h)
      end
    end
  end
end
