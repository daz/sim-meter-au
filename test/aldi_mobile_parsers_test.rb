# frozen_string_literal: true

require "nokogiri"
require "test_helper"

class AldiMobileParsersTest < Minitest::Test
  SERVICE = SimMeterAU::Service.new(id: "1234567", name: "Test SIM", number: "0400000001")

  def test_parses_service_details
    details = SimMeterAU::Providers::AldiMobile::Parsers::ServiceDetails.new.parse(
      page: html(details_html),
      service: SERVICE,
      roaming_enabled: false,
      retrieved_at: Time.utc(2026, 8, 25, 5, 0, 0)
    )

    assert_equal "active_plan", details.status
    assert_equal "$240 Data Plan", details.plan.name
    assert_equal "data", details.plan.type
    assert_equal Date.new(2027, 4, 28), details.plan.expires_on
    assert_equal 246, details.plan.days_remaining
    assert details.plan.auto_recharge
    assert_equal 164 * 1024**3, details.data.plan_remaining_bytes
    assert_equal 0, details.data.rollover_bytes
    assert_equal 164 * 1024**3, details.data.total_remaining_bytes
    assert_equal Date.new(2027, 5, 1), details.payg.expires_on
    assert_equal 249, details.payg.days_until_expiry
    refute details.roaming_enabled
  end

  def test_parses_service_without_an_active_plan
    details = SimMeterAU::Providers::AldiMobile::Parsers::ServiceDetails.new.parse(
      page: html("<div id='service-body'></div>"),
      service: SERVICE,
      roaming_enabled: nil
    )

    assert_equal "no_active_plan", details.status
    assert_nil details.plan
    assert_nil details.data
    assert_nil details.payg
  end

  def test_parses_usage_summary_and_records
    report = SimMeterAU::Providers::AldiMobile::Parsers::Usage.new.parse(
      page: html(usage_html),
      service: SERVICE,
      from: Date.new(2026, 8, 1),
      to: Date.new(2026, 8, 25)
    )

    assert_equal 1, report.summaries.length
    assert_equal "Standard Data", report.summaries.first.type
    assert_equal 23, report.summaries.first.count
    assert_equal "5.98GB", report.summaries.first.rounded_usage
    assert_equal "0.0000", report.summaries.first.charge_dollars
    assert_equal 1, report.records.length
    assert_equal "Standard Data", report.records.first.type
    assert_equal "0400000001", report.records.first.number
    assert_equal "mdata2.net.au", report.records.first.destination
  end

  def test_parses_orders_with_metadata_rows
    orders = SimMeterAU::Providers::AldiMobile::Parsers::Orders.new.parse(html(orders_html))

    assert_equal 1, orders.length
    assert_equal "987654321", orders.first.id
    assert_equal "0400000001", orders.first.number
    assert_equal "$240 Data Plan", orders.first.plan_name
    assert_equal 24_000, orders.first.total_cents
    assert_equal "testref1", orders.first.transaction_reference
  end

  private

  def html(source)
    Nokogiri::HTML(source)
  end

  def details_html
    <<~HTML
      <div id="service-body">
        <div class="panel">
          <div class="panel-heading"><h3 class="panel-title">$240 Data Plan</h3></div>
          <div class="row clearfix"><label class="col-xs-6">Plan data remaining</label><div class="col-xs-6">164 GB</div></div>
          <div class="row clearfix"><label class="col-xs-6">Data rollover</label><div class="col-xs-6">0.00 MB</div></div>
          <div class="row clearfix"><label class="col-xs-6">Total data for you to use</label><div class="col-xs-6">164 GB</div></div>
          <div class="row clearfix"><label class="col-xs-6">Days remaining</label><div class="col-xs-6">246 (Expiry 28/04/2027)</div></div>
          <input id="autorechargeswitch" type="checkbox" checked>
        </div>
        <div class="panel">
          <div class="panel-heading"><h3 class="panel-title">Pay As You Go balance &amp; service expiry</h3></div>
          <div class="row clearfix"><label class="col-xs-6">Days until service expiry</label><div class="col-xs-6">249 (Expiry 01/05/2027)</div></div>
        </div>
      </div>
    HTML
  end

  def usage_html
    <<~HTML
      <table>
        <thead><tr><th>Usage Type</th><th>Count</th><th>Rounded Duration/Data</th><th>Charge</th></tr></thead>
        <tbody><tr><td>Standard Data</td><td>23</td><td>5.98GB</td><td>$0.0000</td></tr></tbody>
      </table>
      <table>
        <thead><tr><th>Number</th><th>Destination</th><th>Duration/Data</th><th>Charge</th><th>Date</th></tr></thead>
        <tbody>
          <tr><td colspan="5">Standard Data</td></tr>
          <tr><td>0400 000 001</td><td>mdata2.net.au</td><td>2.57MB</td><td>$0.0000</td><td>Tue, 25 Aug - 05:50pm</td></tr>
        </tbody>
      </table>
    HTML
  end

  def orders_html
    <<~HTML
      <table>
        <thead><tr><th>Order #</th><th>Number</th><th>Type</th><th>Plan</th><th>Date</th><th>Actions</th></tr></thead>
        <tbody>
          <tr><td>987654321</td><td>0400 000 001</td><td>Plan</td><td>$240 Data Plan</td><td>Tue, 28 Apr - 09:16pm</td><td>-</td></tr>
          <tr><td colspan="5">Total Cost: $240.00 | Transaction Ref: testref1</td></tr>
        </tbody>
      </table>
    HTML
  end
end
