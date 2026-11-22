# frozen_string_literal: true

require "json"
require "optparse"
require "date"

module SimMeterAU
  class CLI
    PROVIDER_COMMANDS = %w[services service].freeze

    def initialize(out: $stdout, err: $stderr, env: ENV, client_factory: nil)
      @out = out
      @err = err
      @env = env
      @client_factory = client_factory || method(:build_client)
    end

    def run(arguments)
      arguments = arguments.dup
      global_options = parse_global_options(arguments)
      return global_options if global_options.is_a?(Integer)

      @provider_name = global_options.fetch(:provider)
      command = arguments.shift || "providers"

      if PROVIDER_COMMANDS.include?(command) && @provider_name.to_s.empty?
        raise ConfigurationError,
          "Select a provider with --provider NAME (available: #{SimMeterAU.providers.join(", ")})"
      end

      case command
      when "providers"
        list_providers(arguments)
      when "services"
        list_services(arguments)
      when "service"
        service_command(arguments)
      when "-h", "--help"
        @out.puts help
        0
      when "-v", "--version"
        @out.puts VERSION
        0
      else
        @err.puts "Unknown command: #{command}"
        @err.puts help
        1
      end
    rescue ConfigurationError, AuthenticationError, ConnectionError,
      UnexpectedResponseError, ServiceNotFoundError, AmbiguousServiceError => error
      @err.puts error.message
      1
    end

    private

    def list_providers(arguments)
      options = {json: false}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sim-meter-au providers [--json]"
        opts.on("--json", "Print providers as JSON") { options[:json] = true }
      end
      parser.parse!(arguments)

      providers = SimMeterAU.providers.map do |key|
        provider_class = SimMeterAU.provider_class(key)
        {key:, name: provider_class.display_name}
      end

      if options[:json]
        @out.puts JSON.pretty_generate(providers)
      else
        print_table(
          ["PROVIDER", "NAME"],
          providers.map { |provider| [provider[:key], provider[:name]] }
        )
      end
      0
    rescue OptionParser::ParseError => error
      option_error(error, parser)
    end

    def parse_global_options(arguments)
      options = {
        provider: nil
      }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sim-meter-au [options] COMMAND"
        opts.on("-p", "--provider NAME", "Provider to use") do |name|
          options[:provider] = name
        end
        opts.on("-h", "--help", "Show this help") { options[:help] = true }
        opts.on("-v", "--version", "Show the gem version") { options[:version] = true }
      end
      parser.order!(arguments)
      if options[:help]
        @out.puts help
        return 0
      end
      if options[:version]
        @out.puts VERSION
        return 0
      end
      options
    rescue OptionParser::ParseError => error
      @err.puts error.message
      @err.puts parser
      1
    end

    def list_services(arguments)
      options = {json: false, details: false}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sim-meter-au services [--details] [--json]"
        opts.on("--details", "Retrieve plan and balance details") { options[:details] = true }
        opts.on("--json", "Print services as JSON") { options[:json] = true }
      end
      parser.parse!(arguments)

      client.authenticate!
      services = client.services
      results = if options[:details]
        services.map { |service| client.service_details(service) }
      else
        services
      end

      if options[:json]
        @out.puts JSON.pretty_generate(results.map(&:to_h))
      elsif options[:details]
        results.each_with_index do |details, index|
          @out.puts if index.positive?
          print_service_details(details)
        end
      else
        print_service_table(services)
      end

      0
    rescue OptionParser::ParseError => error
      @err.puts error.message
      @err.puts parser
      1
    end

    def service_command(arguments)
      identifier = arguments.shift
      raise ConfigurationError, "Usage: sim-meter-au service IDENTIFIER [usage|orders]" if identifier.to_s.empty?

      subcommand = arguments.first
      case subcommand
      when "usage"
        arguments.shift
        service_usage(identifier, arguments)
      when "orders"
        arguments.shift
        service_orders(identifier, arguments)
      else
        service_details(identifier, arguments)
      end
    end

    def service_details(identifier, arguments)
      options = {json: false}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sim-meter-au service IDENTIFIER [--json]"
        opts.on("--json", "Print details as JSON") { options[:json] = true }
      end
      parser.parse!(arguments)

      client.authenticate!
      details = client.service_details(identifier)

      if options[:json]
        @out.puts JSON.pretty_generate(details.to_h)
      else
        print_service_details(details)
      end
      0
    rescue OptionParser::ParseError => error
      option_error(error, parser)
    end

    def service_usage(identifier, arguments)
      options = {
        json: false,
        details: false,
        from: Date.today - 30,
        to: Date.today
      }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sim-meter-au service IDENTIFIER usage [options]"
        opts.on("--from DATE", "Start date in YYYY-MM-DD format") { |date| options[:from] = parse_date(date) }
        opts.on("--to DATE", "End date in YYYY-MM-DD format") { |date| options[:to] = parse_date(date) }
        opts.on("--details", "Include individual usage records") { options[:details] = true }
        opts.on("--json", "Print usage as JSON") { options[:json] = true }
      end
      parser.parse!(arguments)

      client.authenticate!
      report = client.usage(identifier, from: options[:from], to: options[:to])

      if options[:json]
        payload = report.to_h
        payload[:records] = [] unless options[:details]
        payload[:record_count] = report.records.length
        @out.puts JSON.pretty_generate(payload)
      else
        print_usage(report, include_records: options[:details])
      end
      0
    rescue OptionParser::ParseError => error
      option_error(error, parser)
    end

    def service_orders(identifier, arguments)
      options = {json: false}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: sim-meter-au service IDENTIFIER orders [--json]"
        opts.on("--json", "Print orders as JSON") { options[:json] = true }
      end
      parser.parse!(arguments)

      client.authenticate!
      orders = client.orders(identifier)

      if options[:json]
        @out.puts JSON.pretty_generate(orders.map(&:to_h))
      else
        print_orders(orders)
      end
      0
    rescue OptionParser::ParseError => error
      option_error(error, parser)
    end

    def print_service_table(services)
      if services.empty?
        @out.puts "No services found."
        return
      end

      print_table(
        ["NAME", "NUMBER", "SERVICE ID"],
        services.map { |service| [service.name, service.number, service.id] }
      )
    end

    def print_service_details(details)
      service = details.service
      @out.puts "#{service.name} (#{service.number})"
      @out.puts "-" * (service.name.length + service.number.length + 3)
      print_value("Service ID", service.id)
      print_value("Status", details.status.tr("_", " "))

      if details.plan
        @out.puts
        @out.puts "Plan"
        print_value("Name", details.plan.name)
        print_value("Type", details.plan.type)
        print_value("Expires", format_date(details.plan.expires_on))
        print_value("Days remaining", details.plan.days_remaining)
        print_value("Auto recharge", format_boolean(details.plan.auto_recharge))
      else
        @out.puts
        print_value("Plan", "None")
      end

      if details.data
        @out.puts
        @out.puts "Data"
        print_value("Plan remaining", format_bytes(details.data.plan_remaining_bytes))
        print_value("Rollover", format_bytes(details.data.rollover_bytes))
        print_value("Total remaining", format_bytes(details.data.total_remaining_bytes))
      end

      if details.payg
        @out.puts
        @out.puts "PAYG and service"
        print_value("Balance", format_cents(details.payg.balance_cents))
        print_value("Service expires", format_date(details.payg.expires_on))
        print_value("Days until expiry", details.payg.days_until_expiry)
      end

      @out.puts
      print_value("Roaming", format_boolean(details.roaming_enabled))
      print_value("Retrieved", details.retrieved_at.iso8601)
    end

    def print_usage(report, include_records:)
      @out.puts "Usage for #{report.service.name} (#{report.service.number})"
      @out.puts "#{report.from.iso8601} to #{report.to.iso8601}"
      @out.puts

      summary_rows = report.summaries.map do |summary|
        charge = summary.charge_dollars.nil? ? "Unknown" : "$#{summary.charge_dollars}"
        [summary.type, summary.count.to_s, summary.rounded_usage, charge]
      end
      print_table(["TYPE", "COUNT", "ROUNDED USAGE", "CHARGE"], summary_rows)
      @out.puts "No usage found." if summary_rows.empty?
      @out.puts "Individual records: #{report.records.length}"

      return unless include_records && report.records.any?

      @out.puts
      rows = report.records.map do |record|
        [record.type.to_s, record.destination, record.usage, "$#{record.charge_dollars}", record.date_label]
      end
      print_table(["TYPE", "DESTINATION", "USAGE", "CHARGE", "DATE"], rows)
    end

    def print_orders(orders)
      if orders.empty?
        @out.puts "No orders found."
        return
      end

      rows = orders.map do |order|
        [order.id, order.type, order.plan_name, format_cents(order.total_cents), order.date_label]
      end
      print_table(["ORDER", "TYPE", "PLAN", "TOTAL", "DATE"], rows)
    end

    def print_table(headers, rows)
      all_rows = [headers] + rows.map { |row| row.map(&:to_s) }
      widths = all_rows.transpose.map { |column| column.map(&:length).max }

      all_rows.each_with_index do |row, index|
        @out.puts row.each_with_index.map { |value, column| value.ljust(widths[column]) }.join("  ").rstrip
        @out.puts widths.map { |width| "-" * width }.join("  ") if index.zero?
      end
    end

    def print_value(label, value)
      return if value.nil?

      @out.puts format("%-18s %s", "#{label}:", value)
    end

    def format_bytes(bytes)
      return if bytes.nil?
      return "0 B" if bytes.zero?

      units = %w[B KB MB GB TB]
      value = bytes.to_f
      unit = units.shift
      while value >= 1024 && units.any?
        value /= 1024
        unit = units.shift
      end
      precision = value >= 100 ? 0 : value >= 10 ? 1 : 2
      "#{format("%.#{precision}f", value)} #{unit}"
    end

    def format_cents(cents)
      return if cents.nil?

      format("$%.2f", cents / 100.0)
    end

    def format_date(date)
      date&.strftime("%d/%m/%Y")
    end

    def format_boolean(value)
      return "Unknown" if value.nil?

      value ? "Enabled" : "Disabled"
    end

    def parse_date(value)
      Date.iso8601(value)
    rescue Date::Error
      raise OptionParser::InvalidArgument, "invalid date: #{value}"
    end

    def option_error(error, parser)
      @err.puts error.message
      @err.puts parser
      1
    end

    def client
      @client ||= @client_factory.call(provider: @provider_name, **credentials)
    end

    def credentials
      SimMeterAU.provider_class(@provider_name).credentials_from(@env)
    end

    def build_client(provider:, **credentials)
      SimMeterAU.client(provider:, **credentials)
    end

    def help
      <<~HELP
        Usage: sim-meter-au [options] COMMAND

        Provider:
          -p, --provider NAME Select a provider (required for data commands)

        Commands:
          providers         List available providers (default command)
          services          List services on the account
          services --details
                            List details for every service
          service ID        Show plan, data, expiry and roaming details
          service ID usage  Show usage for a date range
          service ID orders Show order history

        Options:
          -h, --help        Show this help
          -v, --version     Show the gem version
      HELP
    end
  end
end
