# frozen_string_literal: true

require "test_helper"

class ProviderTest < Minitest::Test
  def test_lists_registered_providers
    assert_equal [:aldi_mobile], SimMeterAU.providers
  end

  def test_builds_a_provider_through_the_unified_factory
    provider = SimMeterAU.client(
      provider: :aldi,
      login: "0412345678",
      password: "secret-password",
      base_url: "https://example.test"
    )

    assert_instance_of SimMeterAU::Providers::AldiMobile, provider
    assert_kind_of SimMeterAU::Provider, provider
    assert_equal :aldi_mobile, provider.provider
    assert_equal "ALDImobile", provider.class.display_name
  end

  def test_rejects_an_unknown_provider
    error = assert_raises(SimMeterAU::ProviderNotFoundError) do
      SimMeterAU.client(provider: :unknown)
    end

    assert_includes error.message, "Available providers: aldi_mobile"
  end

  def test_base_provider_defines_the_unified_operations
    assert_equal %i[
      authenticate!
      authenticated?
      services
      service
      service_details
      usage
      orders
    ], SimMeterAU::Provider::OPERATIONS
  end

  def test_provider_maps_credentials_from_its_key
    provider_class = SimMeterAU.provider_class(:aldi_mobile)
    environment = {
      "ALDI_MOBILE_LOGIN" => "0412345678",
      "ALDI_MOBILE_PASSWORD" => "secret-password"
    }

    assert_equal %i[login password], provider_class.credential_names
    assert_equal({
      login: "0412345678",
      password: "secret-password"
    }, provider_class.credentials_from(environment))
  end
end
