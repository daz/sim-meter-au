# frozen_string_literal: true

module SimMeterAU
  class Provider
    OPERATIONS = %i[
      authenticate!
      authenticated?
      services
      service
      service_details
      usage
      orders
    ].freeze

    class << self
      def provider_key(value = nil)
        @provider_key = value.to_sym if value
        @provider_key
      end

      def display_name(value = nil)
        @display_name = value.to_s if value
        @display_name || provider_key.to_s
      end

      def credential_names(*names)
        @credential_names = names.map(&:to_sym) unless names.empty?
        @credential_names || []
      end

      def credentials_from(environment)
        prefix = provider_key.to_s.upcase
        credential_names.to_h do |name|
          [name, environment.fetch("#{prefix}_#{name.to_s.upcase}", "")]
        end
      end
    end

    def provider
      self.class.provider_key
    end

    def authenticate!
      unsupported_operation(__method__)
    end

    def login!
      authenticate!
    end

    def authenticated?
      unsupported_operation(__method__)
    end

    def services
      unsupported_operation(__method__)
    end

    def service(_identifier)
      unsupported_operation(__method__)
    end

    def service_details(_identifier)
      unsupported_operation(__method__)
    end

    def usage(_identifier, from:, to:)
      unsupported_operation(__method__)
    end

    def orders(_identifier)
      unsupported_operation(__method__)
    end

    private

    def unsupported_operation(operation)
      raise NotImplementedError,
        "#{self.class} must implement ##{operation}"
    end
  end
end
