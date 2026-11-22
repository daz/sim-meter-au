# frozen_string_literal: true

require "test_helper"

class AldiMobileApiParserTest < Minitest::Test
  SERVICE = SimMeterAU::Service.new(id: "MO123", name: "Test SIM", number: "0400000001")

  def setup
    @parser = SimMeterAU::Providers::AldiMobile::Parsers::Api.new
  end

  def test_converts_balances_dates_and_money_without_rails
    details = parse(plan)
    assert_instance_of SimMeterAU::ServiceDetails, details
    assert_equal "active_plan", details.status
    assert_equal "data", details.plan.type
    assert_equal Date.new(2027, 6, 20), details.plan.expires_on
    assert_equal 211, details.plan.days_remaining
    assert details.plan.auto_recharge
    assert_equal 4 * 1024**3, details.data.plan_remaining_bytes
    assert_equal 2 * 1024**3, details.data.rollover_bytes
    assert_equal 6 * 1024**3, details.data.total_remaining_bytes
    assert_equal 1234, details.payg.balance_cents
    assert_equal Date.new(2027, 6, 22), details.payg.expires_on
    assert_equal 213, details.payg.days_until_expiry
    assert_equal "2027-06-20", details.to_h.dig(:plan, :expires_on)
  end

  def test_payg_only_services_retain_expiry_without_an_active_plan
    details = parse(plan.merge("plan_type" => "PayG", "plan_name" => "SIM Starter", "data_usage" => []))
    assert_equal "no_active_plan", details.status
    assert_nil details.plan
    assert_nil details.data
    assert_equal Date.new(2027, 6, 22), details.payg.expires_on
  end

  def test_zero_balances_and_disabled_auto_recharge_are_preserved
    source = plan.merge("autoRecharge" => "0", "data_usage" => [
      {"plan_data_remaining_value" => 0, "plan_data_unit" => "bytes"},
      {"rollover_data_remaining_value" => 0, "rollover_unit" => "bytes"}
    ])
    details = parse(source)
    assert_equal 0, details.data.total_remaining_bytes
    refute details.plan.auto_recharge
    assert_nil parse(source.merge("autoRecharge" => "unrecognised")).plan.auto_recharge
  end

  def test_blank_rollover_is_unknown_and_retains_known_plan_balance
    source = plan
    source["data_usage"][1]["rollover_data_remaining_value"] = ""
    details = parse(source)
    assert_nil details.data.rollover_bytes
    assert_equal 4 * 1024**3, details.data.total_remaining_bytes
  end

  def test_rejects_missing_malformed_and_negative_balances
    [nil, [], [nil], [{"plan_data_remaining_value" => "invalid", "plan_data_unit" => "bytes"}],
      [{"plan_data_remaining_value" => -1, "plan_data_unit" => "bytes"}],
      [{"plan_data_remaining_value" => "NaN", "plan_data_unit" => "bytes"}],
      [{"plan_data_remaining_value" => 1, "plan_data_unit" => "unknown"}]].each do |usage|
      assert_raises(SimMeterAU::UnexpectedResponseError) { parse(plan.merge("data_usage" => usage)) }
    end
  end

  def test_rejects_missing_plan_and_invalid_dates_without_exposing_values
    [{}, plan.merge("plan_expiry_date" => "private-invalid-date")].each do |source|
      error = assert_raises(SimMeterAU::UnexpectedResponseError) { parse(source) }
      refute_includes error.message, "private-invalid-date"
    end
  end

  def test_usage_units_follow_the_portal_and_missing_summary_charge_is_unknown
    summaries = @parser.usage_summaries([
      {"category" => "Data", "count" => 3, "total_unitquantity" => 2},
      {"category" => "Calls", "count" => 1, "total_unitquantity" => 90},
      {"category" => "Messages", "count" => 2, "total_unitquantity" => 2}
    ])
    assert_equal ["2048.0 B", "90.0 s", "2.0"], summaries.map(&:rounded_usage)
    assert_nil summaries.first.charge_dollars
    assert_equal [3, 1, 2], summaries.map(&:count)
  end

  def test_empty_history_is_accepted_but_missing_history_is_an_error
    assert_empty @parser.usage_summaries([])
    assert_empty @parser.usage_records({"response" => []}, service: SERVICE)
    assert_empty @parser.orders({"SalesOrder" => []}, service: SERVICE)
    assert_raises(SimMeterAU::UnexpectedResponseError) { @parser.usage_summaries(nil) }
    assert_raises(SimMeterAU::UnexpectedResponseError) { @parser.usage_records({}, service: SERVICE) }
    assert_raises(SimMeterAU::UnexpectedResponseError) { @parser.orders({}, service: SERVICE) }
  end

  private

  def parse(source)
    @parser.service_details(source, service: SERVICE, roaming_enabled: false)
  end

  def plan
    {"plan_type" => "Data Plan", "plan_name" => "$125 Data Plan", "plan_expiry_date" => "20-06-2027",
     "plan_expiry_days" => "211", "autoRecharge" => "1",
     "data_usage" => [{"plan_data_remaining_value" => 4, "plan_data_unit" => "GB"},
                      {"rollover_data_remaining_value" => 2, "rollover_unit" => "GB"}],
     "payg" => {"balance" => "12.34", "end_date" => "22-06-2027", "days_left" => "213"}}
  end
end
