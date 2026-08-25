# frozen_string_literal: true

module SimMeterAU
  Plan = Data.define(
    :name,
    :type,
    :expires_on,
    :days_remaining,
    :auto_recharge
  ) do
    include Serializable
  end

  DataBalance = Data.define(
    :plan_remaining_bytes,
    :rollover_bytes,
    :total_remaining_bytes
  ) do
    include Serializable
  end

  Payg = Data.define(
    :balance_cents,
    :expires_on,
    :days_until_expiry
  ) do
    include Serializable
  end

  ServiceDetails = Data.define(
    :service,
    :status,
    :plan,
    :data,
    :payg,
    :roaming_enabled,
    :retrieved_at
  ) do
    include Serializable
  end

  UsageSummary = Data.define(
    :type,
    :count,
    :rounded_usage,
    :charge_dollars
  ) do
    include Serializable
  end

  UsageRecord = Data.define(
    :type,
    :number,
    :destination,
    :usage,
    :charge_dollars,
    :date_label
  ) do
    include Serializable
  end

  UsageReport = Data.define(
    :service,
    :from,
    :to,
    :summaries,
    :records
  ) do
    include Serializable
  end

  Order = Data.define(
    :id,
    :number,
    :type,
    :plan_name,
    :date_label,
    :total_cents,
    :transaction_reference
  ) do
    include Serializable
  end
end
