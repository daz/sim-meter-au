# frozen_string_literal: true

module SimMeterAU
  module Providers
    class AldiMobile
      module Parsers
        class Usage
      def parse(page:, service:, from:, to:)
        UsageReport.new(
          service:,
          from:,
          to:,
          summaries: parse_summaries(page),
          records: parse_records(page)
        )
      end

      private

      def parse_summaries(page)
        table = find_table(page, ["Usage Type", "Count", "Rounded Duration/Data", "Charge"])
        return [] unless table

        table.css("tbody tr").filter_map do |row|
          cells = row.css("td").map { |cell| text(cell) }
          next unless cells.length >= 4

          UsageSummary.new(
            type: cells[0],
            count: cells[1].delete(",").to_i,
            rounded_usage: cells[2],
            charge_dollars: money_string(cells[3])
          )
        end
      end

      def parse_records(page)
        table = find_table(page, ["Number", "Destination", "Duration/Data", "Charge", "Date"])
        return [] unless table

        current_type = nil
        table.css("tbody tr").filter_map do |row|
          cells = row.css("td").map { |cell| text(cell) }
          if cells.length == 1
            current_type = cells.first
            next
          end
          next unless cells.length >= 5

          UsageRecord.new(
            type: current_type,
            number: normalize_number(cells[0]),
            destination: cells[1],
            usage: cells[2],
            charge_dollars: money_string(cells[3]),
            date_label: cells[4]
          )
        end
      end

      def find_table(page, expected_headers)
        page.css("table").find do |table|
          table.css("th").map { |heading| text(heading) } == expected_headers
        end
      end

      def normalize_number(number)
        digits = number.gsub(/\D/, "")
        digits.start_with?("61") ? "0#{digits.delete_prefix("61")}" : digits
      end

      def money_string(value)
        value.to_s.delete_prefix("$").delete(",")
      end

      def text(node)
        node&.text.to_s.gsub(/\s+/, " ").strip
      end
        end
      end
    end
  end
end
