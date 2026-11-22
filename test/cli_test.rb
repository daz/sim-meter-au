# frozen_string_literal: true

require "stringio"
require "test_helper"

class SimMeterAUCLITest < Minitest::Test
  FakeClient = Struct.new(:services, :details, :usage_report, :orders_list) do
    def authenticate!
      self
    end

    def service_details(_identifier)
      details
    end

    def usage(_identifier, from:, to:)
      usage_report
    end

    def orders(_identifier)
      orders_list
    end
  end

  def test_services_command_prints_a_table
    services = [SimMeterAU::Service.new(id: "123", name: "My SIM", number: "0493000000")]
    status, output, error = run_cli(["services"], services:)

    assert_equal 0, status
    assert_includes output, "NAME"
    assert_includes output, "My SIM"
    assert_includes output, "0493000000"
    assert_includes output, "123"
    assert_empty error
  end

  def test_no_arguments_lists_providers
    output = StringIO.new
    error = StringIO.new
    cli = SimMeterAU::CLI.new(out: output, err: error, env: {})

    status = cli.run([])

    assert_equal 0, status
    assert_includes output.string, "PROVIDER"
    assert_includes output.string, "aldi_mobile"
    assert_includes output.string, "ALDImobile"
    assert_empty error.string
  end

  def test_providers_command_prints_json
    output = StringIO.new
    error = StringIO.new
    cli = SimMeterAU::CLI.new(out: output, err: error, env: {})

    status = cli.run(["providers", "--json"])

    assert_equal 0, status
    assert_equal [{"key" => "aldi_mobile", "name" => "ALDImobile"}], JSON.parse(output.string)
    assert_empty error.string
  end

  def test_services_command_prints_json
    services = [SimMeterAU::Service.new(id: "123", name: "My SIM", number: "0493000000")]
    status, output, error = run_cli(["services", "--json"], services:)

    assert_equal 0, status
    assert_equal [{"id" => "123", "name" => "My SIM", "number" => "0493000000"}], JSON.parse(output)
    assert_empty error
  end

  def test_unknown_command_returns_an_error
    status, _output, error = run_cli(["unknown"])

    assert_equal 1, status
    assert_includes error, "Unknown command: unknown"
  end

  def test_data_command_requires_an_explicit_provider
    output = StringIO.new
    error = StringIO.new
    cli = SimMeterAU::CLI.new(out: output, err: error, env: {})

    status = cli.run(["services"])

    assert_equal 1, status
    assert_includes error.string, "Select a provider with --provider NAME"
  end

  def test_provider_option_is_forwarded_to_the_client_factory
    output = StringIO.new
    error = StringIO.new
    captured_provider = nil
    fake_client = FakeClient.new([], nil, nil, [])
    factory = lambda do |provider:, login:, password:|
      captured_provider = provider
      fake_client
    end
    cli = SimMeterAU::CLI.new(out: output, err: error, env: {}, client_factory: factory)

    status = cli.run(["--provider", "aldi", "services"])

    assert_equal 0, status
    assert_equal "aldi", captured_provider
    assert_empty error.string
  end

  def test_service_details_command_prints_json
    details = sample_details
    status, output, error = run_cli(["service", "0400000001", "--json"], details:)

    assert_equal 0, status
    payload = JSON.parse(output)
    assert_equal "0400000001", payload.dig("service", "number")
    assert_equal "$240 Data Plan", payload.dig("plan", "name")
    assert_equal "2027-04-28", payload.dig("plan", "expires_on")
    assert_empty error
  end

  def test_services_details_command_prints_each_service
    details = sample_details
    status, output, error = run_cli(["services", "--details"], services: [details.service], details:)

    assert_equal 0, status
    assert_includes output, "$240 Data Plan"
    assert_includes output, "164 GB"
    assert_empty error
  end

  def test_usage_command_prints_summary_without_individual_records
    report = sample_usage_report
    status, output, error = run_cli(["service", "0400000001", "usage"], usage_report: report)

    assert_equal 0, status
    assert_includes output, "Standard Data"
    assert_includes output, "Individual records: 1"
    refute_includes output, "mdata2.net.au"
    assert_empty error
  end

  def test_orders_command_prints_orders
    order = SimMeterAU::Order.new(
      id: "987654321",
      number: "0400000001",
      type: "Plan",
      plan_name: "$240 Data Plan",
      date_label: "Tue, 28 Apr - 09:16pm",
      total_cents: 24_000,
      transaction_reference: "testref1"
    )
    status, output, error = run_cli(["service", "0400000001", "orders"], orders: [order])

    assert_equal 0, status
    assert_includes output, "987654321"
    assert_includes output, "$240.00"
    assert_empty error
  end

  def test_usage_summary_reports_unavailable_charges_as_unknown
    report = sample_usage_report
    summary = report.summaries.first.with(charge_dollars: nil)
    report = report.with(summaries: [summary])
    status, output, error = run_cli(["service", "0400000001", "usage"], usage_report: report)

    assert_equal 0, status
    assert_includes output, "Unknown"
    assert_empty error
  end

  private

  def run_cli(arguments, services: [], details: nil, usage_report: nil, orders: [])
    output = StringIO.new
    error = StringIO.new
    fake_client = FakeClient.new(services, details, usage_report, orders)
    factory = ->(provider:, login:, password:) { fake_client }
    cli = SimMeterAU::CLI.new(out: output, err: error, env: {}, client_factory: factory)

    status = cli.run(["--provider", "aldi_mobile", *arguments])
    [status, output.string, error.string]
  end

  def sample_details
    service = SimMeterAU::Service.new(id: "1234567", name: "Test SIM", number: "0400000001")
    SimMeterAU::ServiceDetails.new(
      service:,
      status: "active_plan",
      plan: SimMeterAU::Plan.new(
        name: "$240 Data Plan",
        type: "data",
        expires_on: Date.new(2027, 4, 28),
        days_remaining: 246,
        auto_recharge: false
      ),
      data: SimMeterAU::DataBalance.new(
        plan_remaining_bytes: 164 * 1024**3,
        rollover_bytes: 0,
        total_remaining_bytes: 164 * 1024**3
      ),
      payg: SimMeterAU::Payg.new(
        balance_cents: nil,
        expires_on: Date.new(2027, 5, 1),
        days_until_expiry: 249
      ),
      roaming_enabled: false,
      retrieved_at: Time.utc(2026, 8, 25, 5, 0, 0)
    )
  end

  def sample_usage_report
    service = SimMeterAU::Service.new(id: "1234567", name: "Test SIM", number: "0400000001")
    SimMeterAU::UsageReport.new(
      service:,
      from: Date.new(2026, 8, 1),
      to: Date.new(2026, 8, 25),
      summaries: [SimMeterAU::UsageSummary.new(type: "Standard Data", count: 1, rounded_usage: "2.57MB", charge_dollars: "0.0000")],
      records: [SimMeterAU::UsageRecord.new(type: "Standard Data", number: "0400000001", destination: "mdata2.net.au", usage: "2.57MB", charge_dollars: "0.0000", date_label: "Tue, 25 Aug - 05:50pm")]
    )
  end
end
