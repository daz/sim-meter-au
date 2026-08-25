# frozen_string_literal: true

require "date"

module SimMeterAU
  module Providers
    class AldiMobile
      module Parsers
        class ServiceDetails
      QUANTITY_UNITS = {
        "B" => 1,
        "KB" => 1024,
        "MB" => 1024**2,
        "GB" => 1024**3,
        "TB" => 1024**4
      }.freeze

      def parse(page:, service:, roaming_enabled:, retrieved_at: Time.now)
        plan_panel = find_panel(page, excluding: /Pay As You Go/i)
        payg_panel = find_panel(page, including: /Pay As You Go/i)
        plan_rows = resource_rows(plan_panel)
        payg_rows = resource_rows(payg_panel)
        plan = parse_plan(plan_panel, plan_rows)

        SimMeterAU::ServiceDetails.new(
          service:,
          status: plan ? "active_plan" : "no_active_plan",
          plan:,
          data: parse_data(plan_rows),
          payg: parse_payg(payg_rows),
          roaming_enabled:,
          retrieved_at:
        )
      end

      private

      def find_panel(page, including: nil, excluding: nil)
        page.css("#service-body .panel").find do |panel|
          heading = text(panel.at_css("h3.panel-title"))
          next false if heading.empty?
          next false if including && !heading.match?(including)
          next false if excluding && heading.match?(excluding)

          true
        end
      end

      def resource_rows(panel)
        return {} unless panel

        panel.css(".row.clearfix").to_h do |row|
          label = text(row.at_css("label"))
          value = text(row.css(".col-xs-6").last)
          [label, value]
        end.reject { |label, _value| label.empty? }
      end

      def parse_plan(panel, rows)
        return unless panel

        name = text(panel.at_css("h3.panel-title"))
        days, expiry = parse_expiry(rows["Days remaining"])
        auto_recharge = panel.at_css("#autorechargeswitch")&.key?("checked")

        Plan.new(
          name:,
          type: plan_type(name),
          expires_on: expiry,
          days_remaining: days,
          auto_recharge:
        )
      end

      def parse_data(rows)
        values = {
          plan_remaining_bytes: parse_bytes(rows["Plan data remaining"]),
          rollover_bytes: parse_bytes(rows["Data rollover"]),
          total_remaining_bytes: parse_bytes(rows["Total data for you to use"])
        }
        return if values.values.all?(&:nil?)

        DataBalance.new(**values)
      end

      def parse_payg(rows)
        balance_label = rows.keys.find { |label| label.match?(/Pay As You Go.*balance/i) }
        days, expiry = parse_expiry(rows["Days until service expiry"])
        balance = parse_money(rows[balance_label]) if balance_label
        return if balance.nil? && expiry.nil? && days.nil?

        Payg.new(
          balance_cents: balance,
          expires_on: expiry,
          days_until_expiry: days
        )
      end

      def parse_expiry(value)
        return [nil, nil] if value.to_s.empty?

        days = value[/\A\d+/]&.to_i
        date = value[/Expiry\s+(\d{2}\/\d{2}\/\d{4})/, 1]
        expiry = Date.strptime(date, "%d/%m/%Y") if date
        [days, expiry]
      end

      def parse_bytes(value)
        match = /([\d,.]+)\s*(B|KB|MB|GB|TB)\b/i.match(value.to_s)
        return unless match

        number = match[1].delete(",").to_f
        (number * QUANTITY_UNITS.fetch(match[2].upcase)).round
      end

      def parse_money(value)
        amount = value.to_s[/\$\s*([\d,]+(?:\.\d+)?)/, 1]
        return unless amount

        (amount.delete(",").to_f * 100).round
      end

      def plan_type(name)
        case name
        when /Family Plan/i then "family"
        when /Mobile Plan/i then "mobile"
        when /Data Plan/i then "data"
        when /Super Pack/i then "super_pack"
        else "unknown"
        end
      end

      def text(node)
        node&.text.to_s.gsub(/\s+/, " ").strip
      end
        end
      end
    end
  end
end
