# frozen_string_literal: true

module SimMeterAU
  Service = Data.define(:id, :name, :number) do
    include Serializable
  end
end
