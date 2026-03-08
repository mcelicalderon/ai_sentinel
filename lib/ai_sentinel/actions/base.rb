# frozen_string_literal: true

require 'resolv'
require 'uri'

module AiSentinel
  module Actions
    class Base
      attr_reader :step, :context, :configuration

      def initialize(step:, context:, configuration:)
        @step = step
        @context = context
        @configuration = configuration
      end

      def call
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      private

      def interpolate(value)
        context.interpolate(value)
      end

      def validate_url!(url)
        uri = URI.parse(url)
        host = uri.host
        return unless host

        addrs = Resolv.getaddresses(host)
        addrs.each do |addr|
          ip = IPAddr.new(addr)
          if ip.private? || ip.loopback? || ip.link_local?
            raise Error, "Request to private/internal address is not allowed: #{host} (#{addr})"
          end
        end
      rescue URI::InvalidURIError
        raise Error, "Invalid URL: #{url}"
      end
    end
  end
end
