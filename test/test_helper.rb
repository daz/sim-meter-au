# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"
require "sim_meter_au"

WebMock.disable_net_connect!(allow_localhost: false)
