# Sim Meter AU

Sim Meter AU provides a unified Ruby API for retrieving services, plan details,
data balances, expiry dates and usage from Australian mobile providers.

## Installation

Add the gem to your Gemfile:

```ruby
gem "sim-meter-au"
```

Then install it:

```sh
bundle install
```

## Providers

The currently available provider is:

- `:aldi_mobile` — ALDImobile

Every provider inherits from `SimMeterAU::Provider` and implements the same
operations: authentication, services, service details, usage and orders. **Pull requests welcome**.

Use `SimMeterAU.providers` to get the registered provider names.

## Ruby API

Create a client by selecting a provider and supplying that provider's
credentials:

```ruby
require "sim_meter_au"

client = SimMeterAU.client(
  provider: :aldi_mobile,
  login: ENV.fetch("ALDI_MOBILE_LOGIN"),
  password: ENV.fetch("ALDI_MOBILE_PASSWORD")
)

client.authenticate!
```

### Services

List every service on the account:

```ruby
services = client.services
services.map(&:to_h)
```

```ruby
[
  {id: "1234567", name: "Data SIM", number: "0400000001"},
  {id: "7654321", name: "Camera", number: "0400000002"}
]
```

### Service details

A service can be selected by its provider ID, mobile number or unique nickname:

```ruby
details = client.service_details("0400000001")
details.to_h
```

```ruby
{
  service: {
    id: "1234567",
    name: "Data SIM",
    number: "0400000001"
  },
  status: "active_plan",
  plan: {
    name: "$240 Data Plan",
    type: "data",
    expires_on: "2027-04-28",
    days_remaining: 246,
    auto_recharge: false
  },
  data: {
    plan_remaining_bytes: 176_093_659_136,
    rollover_bytes: 0,
    total_remaining_bytes: 176_093_659_136
  },
  payg: {
    balance_cents: nil,
    expires_on: "2027-05-01",
    days_until_expiry: 249
  },
  roaming_enabled: false,
  retrieved_at: "2026-08-25T05:00:00Z"
}
```

### Other available API

- `SimMeterAU.providers` lists the registered provider names.
- `SimMeterAU.provider_class(provider)` returns the adapter class for a provider.
- `client.provider` returns the selected provider name.
- `client.service(identifier)` finds a service by provider ID, mobile number or
  unique nickname.
- `client.usage(identifier, from:, to:)` retrieves usage summaries and
  individual usage records. Dates may be `Date` objects or ISO date strings.
- `client.orders(identifier)` retrieves order history, costs and transaction
  references.
- `client.authenticated?` reports whether the current provider session is
  authenticated.

## Command-line utility

The gem includes a provider-aware `sim-meter-au` command. For local development,
put the provider credentials in a `.env` file:

```dotenv
ALDI_MOBILE_LOGIN=0412345678
ALDI_MOBILE_PASSWORD=your-password
```

Provider selection is explicit. Pass `--provider NAME` or `-p NAME` before each
data command. Credential environment variables follow the provider key, so a
future `example_mobile` adapter can declare variables such as
`EXAMPLE_MOBILE_LOGIN` and `EXAMPLE_MOBILE_PASSWORD`.

Run the command without arguments, or use the `providers` command, to see the
available providers:

```sh
bundle exec sim-meter-au
bundle exec sim-meter-au providers
```

```text
PROVIDER     NAME
-----------  ----------
aldi_mobile  ALDImobile
```

### Services

```sh
bundle exec sim-meter-au --provider aldi_mobile services
```

```text
NAME      NUMBER      SERVICE ID
--------  ----------  ----------
Data SIM  0400000001  1234567
Camera    0400000002  7654321
```

### Service details

```sh
bundle exec sim-meter-au --provider aldi_mobile service 0400000001
```

```text
Data SIM (0400000001)
---------------------
Service ID:        1234567
Status:            active plan

Plan
Name:              $240 Data Plan
Type:              data
Expires:           28/04/2027
Days remaining:    246
Auto recharge:     Disabled

Data
Plan remaining:    164 GB
Rollover:          0 B
Total remaining:   164 GB

PAYG and service
Service expires:   01/05/2027
Days until expiry: 249

Roaming:           Disabled
Retrieved:         2026-08-25T15:00:00+10:00
```

There is also a `--json` option for all data commands if you need formatted
output.

### Available commands

```sh
# List available providers
bundle exec sim-meter-au
bundle exec sim-meter-au providers

# Select a provider explicitly
bundle exec sim-meter-au --provider aldi_mobile services

# List services
bundle exec sim-meter-au --provider aldi_mobile services

# Retrieve details for every service
bundle exec sim-meter-au --provider aldi_mobile services --details

# Retrieve details for one service
bundle exec sim-meter-au --provider aldi_mobile service IDENTIFIER

# Retrieve a usage summary for the last 30 days
bundle exec sim-meter-au --provider aldi_mobile service IDENTIFIER usage

# Query a specific usage range
bundle exec sim-meter-au --provider aldi_mobile service IDENTIFIER usage \
  --from 2026-08-01 \
  --to 2026-08-25

# Include individual usage records
bundle exec sim-meter-au --provider aldi_mobile service IDENTIFIER usage --details

# Retrieve order history
bundle exec sim-meter-au --provider aldi_mobile service IDENTIFIER orders

# Show help or the gem version
bundle exec sim-meter-au --help
bundle exec sim-meter-au --version
```

Sim Meter AU is not affiliated with or endorsed by any supported provider,
including ALDI or Medion Australia.

## License

Sim Meter AU is available under the [MIT License](LICENSE.md).
