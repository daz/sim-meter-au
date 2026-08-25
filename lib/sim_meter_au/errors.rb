# frozen_string_literal: true

module SimMeterAU
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ProviderNotFoundError < ConfigurationError; end
  class AuthenticationError < Error; end
  class ConnectionError < Error; end
  class UnexpectedResponseError < Error; end
  class ServiceNotFoundError < Error; end
  class AmbiguousServiceError < Error; end
end
