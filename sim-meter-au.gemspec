# frozen_string_literal: true

require_relative "lib/sim_meter_au/version"

Gem::Specification.new do |spec|
  spec.name = "sim-meter-au"
  spec.version = SimMeterAU::VERSION
  spec.authors = ["Darren Jeacocke"]
  spec.email = ["dazonic@me.com"]

  spec.summary = "A unified Ruby API for Australian mobile service accounts"
  spec.description = "Exposes mobile services, balances, expiry and usage through provider adapters."
  spec.homepage = "https://github.com/daz/sim-meter-au"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"
  spec.metadata = {
    "source_code_uri" => "https://github.com/daz/sim-meter-au",
    "bug_tracker_uri" => "https://github.com/daz/sim-meter-au/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE.md"]
  spec.bindir = "exe"
  spec.executables = ["sim-meter-au"]
  spec.require_paths = ["lib"]

  spec.add_dependency "mechanize", "~> 2.14"
  spec.add_dependency "dotenv", "~> 3.2"
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "webmock", "~> 3.24"
end
