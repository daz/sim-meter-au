# frozen_string_literal: true

require "bigdecimal"

module SimMeterAU
  module Providers
    class AldiMobile
      module Parsers
        class Api
          BYTE_UNITS = {"bytes" => 1, "b" => 1, "kb" => 1024, "mb" => 1024**2,
                        "gb" => 1024**3, "tb" => 1024**4}.freeze
          PLAN_TYPES = {"data plan" => "data", "mobile plan" => "mobile",
                        "family plan" => "family", "super pack" => "super_pack"}.freeze

          def service_details(result, service:, roaming_enabled:, retrieved_at: Time.now)
            hash!(result)
            if blank?(result["plan_type"]) || blank?(result["plan_name"])
              invalid!("plan details were not found")
            end
            type = result["plan_type"].to_s.downcase
            plan = unless ["payg", "pay as you go"].include?(type)
              Plan.new(name: result["plan_name"], type: PLAN_TYPES.fetch(type, "unknown"),
                expires_on: date(result["plan_expiry_date"]), days_remaining: integer(result["plan_expiry_days"]),
                auto_recharge: boolean(result["autoRecharge"]))
            end
            usage = result["data_usage"]
            invalid!("data balances were not found") unless usage.is_a?(Array)
            values = usage.reduce({}) { |all, item| all.merge(hash!(item)) }
            remaining = bytes(values["plan_data_remaining_value"], values["plan_data_unit"])
            rollover = bytes(values["rollover_data_remaining_value"], values["rollover_unit"])
            invalid!("plan data balance was not found") if plan && remaining.nil?
            data = if remaining || rollover
              DataBalance.new(plan_remaining_bytes: remaining, rollover_bytes: rollover,
                total_remaining_bytes: remaining.to_i + rollover.to_i)
            end
            payg = result["payg"]
            payg = if payg.is_a?(Hash)
              Payg.new(balance_cents: cents(payg["balance"]), expires_on: date(payg["end_date"]),
                days_until_expiry: integer(payg["days_left"]))
            end
            SimMeterAU::ServiceDetails.new(service:, status: plan ? "active_plan" : "no_active_plan",
              plan:, data:, payg:, roaming_enabled:, retrieved_at:)
          rescue ArgumentError, TypeError
            invalid!("returned invalid plan or balance values")
          end

          def usage_summaries(result)
            array!(result).map do |item|
              hash!(item)
              category = item.fetch("category")
              UsageSummary.new(type: category, count: Integer(item.fetch("count")),
                rounded_usage: usage_quantity(category, item.fetch("total_unitquantity")),
                charge_dollars: nil)
            end
          rescue KeyError, ArgumentError, TypeError
            invalid!("returned invalid usage summaries")
          end

          def usage_records(result, service:)
            array!(hash!(result).fetch("response")).flat_map do |group|
              hash!(group)
              category = group.fetch("category")
              array!(group.fetch("details")).map do |item|
                hash!(item)
                UsageRecord.new(type: item.fetch("type"),
                  number: local_number(item["originatingNumber"] || service.number),
                  destination: item.fetch("destination"),
                  usage: usage_quantity(category, item.fetch("volume")),
                  charge_dollars: decimal(item.fetch("charge")).to_s("F"),
                  date_label: item.fetch("dateTime"))
              end
            end
          rescue KeyError, ArgumentError, TypeError
            invalid!("returned invalid usage records")
          end

          def orders(result, service:)
            array!(hash!(result).fetch("SalesOrder")).map do |item|
              hash!(item)
              Order.new(id: item.fetch("orderNo"), number: local_number(item["serviceIdentifier"] || service.number),
                type: item.fetch("type"), plan_name: item["basePackageName"],
                date_label: item.fetch("createdTime"), total_cents: cents(item["soTotal"]),
                transaction_reference: item["transactionId"])
            end
          rescue KeyError, ArgumentError, TypeError
            invalid!("returned invalid orders")
          end

          private

          def blank?(value)
            value.nil? || value.to_s.strip.empty?
          end

          def hash!(value)
            invalid!("returned an unexpected object") unless value.is_a?(Hash)
            value
          end

          def array!(value)
            invalid!("returned an unexpected list") unless value.is_a?(Array)
            value
          end

          def invalid!(message)
            raise UnexpectedResponseError, "ALDImobile #{message}"
          end

          def decimal(value)
            number = BigDecimal(value.to_s)
            invalid!("returned a non-finite quantity") unless number.finite?
            number
          end

          def bytes(value, unit)
            return if blank?(value)
            multiplier = BYTE_UNITS[unit.to_s.downcase]
            invalid!("returned an unknown data unit") unless multiplier
            amount = decimal(value)
            invalid!("returned a negative data balance") if amount.negative?
            (amount * multiplier).round
          end

          def cents(value)
            (decimal(value) * 100).round unless blank?(value)
          end

          def date(value)
            return if blank?(value)
            Date.strptime(value, "%d-%m-%Y")
          end

          def integer(value)
            Integer(value) unless blank?(value)
          end

          def boolean(value)
            return true if [true, "true", 1, "1"].include?(value)
            return false if [false, "false", 0, "0"].include?(value)
            nil
          end

          def local_number(value)
            value.to_s.gsub(/\D/, "").sub(/\A61/, "0")
          end

          def usage_quantity(category, value)
            quantity = decimal(value)
            case category.to_s.downcase
            when "data" then "#{(quantity * 1024).to_s("F")} B"
            when "call", "calls" then "#{quantity.to_s("F")} s"
            else quantity.to_s("F")
            end
          end
        end
      end
    end
  end
end
