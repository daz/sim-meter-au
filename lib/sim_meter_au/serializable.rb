# frozen_string_literal: true

require "date"

module SimMeterAU
  module Serializable
    def to_h
      members.to_h do |member|
        [member, serialize_value(public_send(member))]
      end
    end

    private

    def serialize_value(value)
      case value
      when Serializable
        value.to_h
      when Array
        value.map { |item| serialize_value(item) }
      when Date, Time
        value.iso8601
      else
        value
      end
    end
  end
end
