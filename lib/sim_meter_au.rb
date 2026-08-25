# frozen_string_literal: true

require_relative "sim_meter_au/version"
require_relative "sim_meter_au/errors"
require_relative "sim_meter_au/serializable"
require_relative "sim_meter_au/service"
require_relative "sim_meter_au/models"
require_relative "sim_meter_au/provider"
require_relative "sim_meter_au/providers/aldi_mobile"
require_relative "sim_meter_au/providers/aldi_mobile/parsers/service_details"
require_relative "sim_meter_au/providers/aldi_mobile/parsers/usage"
require_relative "sim_meter_au/providers/aldi_mobile/parsers/orders"
require_relative "sim_meter_au/cli"

module SimMeterAU
  PROVIDERS = {
    aldi_mobile: Providers::AldiMobile
  }.freeze

  PROVIDER_ALIASES = {
    aldi: :aldi_mobile,
    aldimobile: :aldi_mobile
  }.freeze

  def self.client(provider:, **options)
    provider_class(provider).new(**options)
  end

  def self.provider_class(provider)
    key = normalize_provider(provider)
    PROVIDERS.fetch(key)
  rescue KeyError
    available = PROVIDERS.keys.join(", ")
    raise ProviderNotFoundError,
      "Unknown provider #{provider.inspect}. Available providers: #{available}"
  end

  def self.providers
    PROVIDERS.keys
  end

  def self.normalize_provider(provider)
    key = provider.to_s.downcase.tr("- ", "_").to_sym
    PROVIDER_ALIASES.fetch(key, key)
  end
  private_class_method :normalize_provider
end
