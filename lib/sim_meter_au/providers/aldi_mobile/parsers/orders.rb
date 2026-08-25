# frozen_string_literal: true

module SimMeterAU
  module Providers
    class AldiMobile
      module Parsers
        class Orders
      HEADERS = ["Order #", "Number", "Type", "Plan", "Date", "Actions"].freeze

      def parse(page)
        table = page.css("table").find do |candidate|
          candidate.css("th").map { |heading| text(heading) } == HEADERS
        end
        return [] unless table

        orders = []
        current = nil

        table.css("tbody tr").each do |row|
          cells = row.css("td").map { |cell| text(cell) }
          if cells.length >= 6
            orders << build_order(current) if current
            current = {
              id: cells[0],
              number: normalize_number(cells[1]),
              type: cells[2],
              plan_name: cells[3],
              date_label: cells[4]
            }
          elsif current && cells.length == 1
            current[:total_cents] = parse_total(cells[0])
            current[:transaction_reference] = cells[0][/Transaction Ref:\s*([^\s]+)/i, 1]
          end
        end

        orders << build_order(current) if current
        orders
      end

      private

      def build_order(attributes)
        Order.new(
          id: attributes[:id],
          number: attributes[:number],
          type: attributes[:type],
          plan_name: attributes[:plan_name],
          date_label: attributes[:date_label],
          total_cents: attributes[:total_cents],
          transaction_reference: attributes[:transaction_reference]
        )
      end

      def parse_total(value)
        amount = value[/Total Cost:\s*\$([\d,]+(?:\.\d+)?)/i, 1]
        return unless amount

        (amount.delete(",").to_f * 100).round
      end

      def normalize_number(number)
        digits = number.gsub(/\D/, "")
        digits.start_with?("61") ? "0#{digits.delete_prefix("61")}" : digits
      end

      def text(node)
        node&.text.to_s.gsub(/\s+/, " ").strip
      end
        end
      end
    end
  end
end
