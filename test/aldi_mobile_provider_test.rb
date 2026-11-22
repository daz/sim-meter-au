# frozen_string_literal: true

require "test_helper"

class AldiMobileProviderTest < Minitest::Test
  BASE_URL = "https://example.test/dx-sync"

  def test_authenticates_with_json_and_loads_services
    login = stub_login
    client = build_client
    refute client.authenticated?
    assert_same client, client.authenticate!
    assert client.authenticated?
    assert_equal %w[MO123 MO456], client.services.map(&:id)
    assert_requested login, times: 1
  end

  def test_normalizes_international_and_account_logins
    ["+61 400 000 001", "61400000001", "40012345"].each do |login|
      mobile = login != "40012345"
      stub_request(:post, "#{BASE_URL}/crm/v1/login")
        .with(headers: {"Type" => mobile ? "msisdn" : "accountNo"},
          body: {username: mobile ? "61400000001" : login, password: "secret-password", source: "app"}.to_json)
        .to_return(api_response("accessToken" => "account-token"))
      stub_profile
      assert build_client(login:).authenticate!.authenticated?
    end
  end

  def test_services_require_an_authenticated_session
    error = assert_raises(SimMeterAU::AuthenticationError) { build_client.services }
    assert_equal "Log in before requesting services", error.message
  end

  def test_finds_a_service_by_id_number_name_or_service_object
    stub_login
    client = build_client.authenticate!
    ["MO123", "0400 000 001", "+61 400 000 001", "test sim", client.services.first].each do |identifier|
      assert_equal "MO123", client.service(identifier).id
    end
    assert_raises(SimMeterAU::ServiceNotFoundError) { client.service("missing") }
    assert_raises(SimMeterAU::ServiceNotFoundError) do
      client.service(SimMeterAU::Service.new(id: "foreign", number: "0400000999", name: "Other"))
    end
  end

  def test_ambiguous_nicknames_raise
    stub_login(services: service_list.map { |item| item.merge("servicename" => "Camera") })
    assert_raises(SimMeterAU::AmbiguousServiceError) { build_client.authenticate!.service("camera") }
  end

  # Preserves the existing regression test for reading every service, using the new API.
  def test_retrieves_details_for_every_service_discovered_on_the_account
    stub_login
    switches = service_list.each_with_index.map do |item, index|
      token = "service-#{index}"
      stub_request(:get, "#{BASE_URL}/crm/v1/profile").with(headers: {"Token" => token})
        .to_return(api_response("irServices" => [{"selfcare_ir_status" => index.zero? ? "Disable" : "Enable"}]))
      stub_request(:get, "#{BASE_URL}/crm/v1/fetch/currentPlanDetails").with(headers: {"Token" => token})
        .to_return(api_response(plan_details))
      stub_switch(item["serviceAccountNo"], item["msisdn"], token:)
    end
    client = build_client.authenticate!
    details = client.services.map { |service| client.service_details(service) }
    assert_equal %w[MO123 MO456], details.map { |item| item.service.id }
    assert_equal [false, true], details.map(&:roaming_enabled)
    assert_equal [6 * 1024**3] * 2, details.map { |item| item.data.total_remaining_bytes }
    assert client.authenticated?
    switches.each { |switch| assert_requested switch, times: 1 }
  end

  def test_service_switch_uses_account_token_and_omits_tenant_headers
    stub_login
    stub_switch
    client = build_client.authenticate!
    client.send(:service_token, client.services.first)
    assert_requested :post, "#{BASE_URL}/crm/v1/login", times: 1 do |request|
      !request.headers.key?("Tenancyid") && !request.headers.key?("Appid") &&
        request.headers["Token"] == "account-token"
    end
  end

  def test_rejects_a_switch_to_the_wrong_service
    stub_login
    stub_switch(returned_id: "MO999")
    client = build_client.authenticate!
    assert_raises(SimMeterAU::UnexpectedResponseError) { client.service_details("MO123") }
  end

  def test_rejects_empty_credentials_before_connecting
    assert_raises(SimMeterAU::ConfigurationError) { build_client(login: " ") }
    assert_raises(SimMeterAU::ConfigurationError) { build_client(password: "") }
  end

  def test_authentication_failure_does_not_expose_credentials_or_provider_body
    stub_request(:post, "#{BASE_URL}/crm/v1/login")
      .to_return(api_response({"arguments" => {"statusCode" => "401", "errorMessage" => "secret-password"}}, success: false))
    client = build_client
    error = assert_raises(SimMeterAU::AuthenticationError) { client.authenticate! }
    refute_includes error.message, "secret-password"
    refute client.authenticated?
  end

  def test_failed_reauthentication_clears_the_old_session
    stub_login
    client = build_client.authenticate!
    stub_request(:post, "#{BASE_URL}/crm/v1/login").to_return(status: 503)
    assert_raises(SimMeterAU::ConnectionError) { client.authenticate! }
    refute client.authenticated?
    assert_raises(SimMeterAU::AuthenticationError) { client.services }
  end

  def test_expired_service_tokens_clear_authentication_state
    stub_login
    stub_switch
    stub_request(:get, "#{BASE_URL}/crm/v1/getSalesOrders")
      .with(query: {pageNo: 1, noOfRecords: 100})
      .to_return(api_response({"arguments" => {"statusCode" => "401"}}, success: false))
    client = build_client.authenticate!
    assert_raises(SimMeterAU::AuthenticationError) { client.orders("MO123") }
    refute client.authenticated?
    assert_raises(SimMeterAU::AuthenticationError) { client.services }
  end

  def test_expired_passwords_and_missing_tokens_do_not_authenticate
    [{"isPasswordExpired" => true, "accessToken" => "expired"}, {}].each do |result|
      stub_request(:post, "#{BASE_URL}/crm/v1/login").to_return(api_response(result))
      client = build_client
      assert_raises(SimMeterAU::Error) { client.authenticate! }
      refute client.authenticated?
    end
  end

  def test_handles_http_and_network_failures
    {401 => SimMeterAU::AuthenticationError, 403 => SimMeterAU::AuthenticationError,
      404 => SimMeterAU::UnexpectedResponseError, 429 => SimMeterAU::ConnectionError,
      503 => SimMeterAU::ConnectionError}.each do |status, klass|
      stub_request(:post, "#{BASE_URL}/crm/v1/login").to_return(status:, body: "private response")
      error = assert_raises(klass) { build_client.authenticate! }
      refute_includes error.message, "private response"
    end
    stub_request(:post, "#{BASE_URL}/crm/v1/login").to_timeout
    assert_raises(SimMeterAU::ConnectionError) { build_client.authenticate! }
  end

  def test_api_outages_inside_http_200_are_retryable
    stub_request(:post, "#{BASE_URL}/crm/v1/login")
      .to_return(api_response({"arguments" => {"statusCode" => "503"}}, success: false))
    assert_raises(SimMeterAU::ConnectionError) { build_client.authenticate! }
  end

  def test_rejects_invalid_json_missing_service_lists_and_non_object_results
    ["<html>maintenance</html>", "[]", '{"response":{"success":true,"result":null}}'].each do |body|
      stub_request(:post, "#{BASE_URL}/crm/v1/login").to_return(status: 200, body:)
      assert_raises(SimMeterAU::UnexpectedResponseError) { build_client.authenticate! }
    end
    stub_login
    stub_request(:get, "#{BASE_URL}/crm/v1/profile").to_return(api_response({}))
    client = build_client
    assert_raises(SimMeterAU::UnexpectedResponseError) { client.authenticate! }
    refute client.authenticated?
  end

  def test_orders_fetch_all_pages
    stub_login
    stub_switch
    [1, 2].each do |page|
      stub_request(:get, "#{BASE_URL}/crm/v1/getSalesOrders")
        .with(query: {pageNo: page, noOfRecords: 100}, headers: {"Token" => "service-token"})
        .to_return(api_response("SalesOrder" => [order.merge("orderNo" => "order-#{page}")], "totalRecords" => "2"))
    end
    orders = build_client.authenticate!.orders("MO123")
    assert_equal %w[order-1 order-2], orders.map(&:id)
    assert_equal [12_500, 12_500], orders.map(&:total_cents)
    assert_equal ["0400000001"] * 2, orders.map(&:number)
  end

  def test_incomplete_order_pagination_is_an_error
    stub_login
    stub_switch
    stub_request(:get, "#{BASE_URL}/crm/v1/getSalesOrders").with(query: {pageNo: 1, noOfRecords: 100})
      .to_return(api_response("SalesOrder" => [], "totalRecords" => "2"))
    assert_raises(SimMeterAU::UnexpectedResponseError) { build_client.authenticate!.orders("MO123") }
  end

  def test_usage_fetches_summaries_and_all_categories_with_pagination
    stub_login
    stub_switch
    dates = {start: "11-01-2026", end: "11-22-2026"}
    stub_request(:get, "#{BASE_URL}/usage/v1/Usagesummary").with(query: dates)
      .to_return(api_response([{"category" => "Data", "count" => 2, "total_unitquantity" => 2048}]))
    %w[Call SMS Data].each do |category|
      pages = category == "Data" ? [1, 2] : [1]
      pages.each do |page|
        items = category == "Data" ? [usage_record] : []
        stub_request(:get, "#{BASE_URL}/usage/v1/Usagedetails")
          .with(query: dates.merge(category:, usageType: "ALL", size: 100, page:), headers: {"Token" => "service-token"})
          .to_return(api_response("response" => [{"category" => category.downcase, "details" => items}], "totalRecords" => category == "Data" ? 2 : 0))
      end
    end
    report = build_client.authenticate!.usage("MO123", from: "2026-11-01", to: "2026-11-22")
    assert_equal 2, report.records.length
    assert_equal "2048.0 B", report.records.first.usage
    assert_equal "0.01", report.records.first.charge_dollars
    assert_equal "2097152.0 B", report.summaries.first.rounded_usage
    assert_equal Date.new(2026, 11, 1), report.from
  end

  def test_usage_dates_are_validated_before_requests
    client = build_client
    [["bad-date", "2026-11-22"], ["2026-11-23", "2026-11-22"], ["2020-01-01", "2026-11-22"]].each do |from, to|
      assert_raises(SimMeterAU::ConfigurationError) { client.usage("MO123", from:, to:) }
    end
  end

  private

  def build_client(login: "0400000001", password: "secret-password")
    SimMeterAU.client(provider: :aldi_mobile, login:, password:, base_url: BASE_URL)
  end

  def api_response(result = nil, success: true, **fields)
    result ||= fields
    {status: 200, headers: {"Content-Type" => "application/json"},
     body: {response: {success: success.to_s, result:}}.to_json}
  end

  def stub_login(services: service_list)
    request = stub_request(:post, "#{BASE_URL}/crm/v1/login")
      .with(headers: {"Tenancyid" => "SP_ALDIMOBILE_AUS", "Appid" => SimMeterAU::Providers::AldiMobile::APP_ID,
                     "Type" => "msisdn", "Operation" => "customerLogin"},
        body: {username: "61400000001", password: "secret-password", source: "app"}.to_json)
      .to_return(api_response("accessToken" => "account-token"))
    stub_profile(services:)
    request
  end

  def stub_profile(services: service_list)
    stub_request(:get, "#{BASE_URL}/crm/v1/profile").with(headers: {"Token" => "account-token"})
      .to_return(api_response("serviceList" => services))
  end

  def stub_switch(id = "MO123", number = "61400000001", token: "service-token", returned_id: id)
    stub_request(:post, "#{BASE_URL}/crm/v1/login")
      .with(headers: {"Token" => "account-token", "Type" => "msisdn"},
        body: {username: number, password: nil, source: "app", accountNo: id}.to_json)
      .to_return(api_response("accessToken" => token, "primaryDevice" => {"accountNo" => returned_id}))
  end

  def service_list
    [{"serviceAccountNo" => "MO123", "msisdn" => "61400000001", "servicename" => "Test SIM"},
     {"serviceAccountNo" => "MO456", "msisdn" => "61400000002", "servicename" => "Test Camera"}]
  end

  def plan_details
    {"plan_type" => "Data Plan", "plan_name" => "$125 Data Plan", "plan_expiry_date" => "20-06-2027",
     "plan_expiry_days" => "211", "autoRecharge" => "1",
     "data_usage" => [{"plan_data_remaining_value" => 4 * 1024**3, "plan_data_unit" => "bytes"},
                      {"rollover_data_remaining_value" => 2 * 1024**3, "rollover_unit" => "bytes"}],
     "payg" => {"balance" => "12.34", "end_date" => "22-06-2027", "days_left" => "213"}}
  end

  def order
    {"orderNo" => "order-1", "serviceIdentifier" => "61400000001", "type" => "Recharge",
     "basePackageName" => "$125 Data Plan", "soTotal" => "125.00", "transactionId" => "ref-1",
     "createdTime" => "2026-11-01T12:30:00Z"}
  end

  def usage_record
    {"destination" => "mdata.net.au", "type" => "Standard Data", "volume" => 2.0,
     "charge" => 0.01, "dateTime" => "2026-11-22T12:00:00Z", "originatingNumber" => "61400000001"}
  end
end
