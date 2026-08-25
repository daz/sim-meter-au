# frozen_string_literal: true

require "mechanize"
require "openssl"
require "json"
require "date"

module SimMeterAU
  module Providers
    class AldiMobile < Provider
      provider_key :aldi_mobile
      display_name "ALDImobile"
      credential_names :login, :password
    DEFAULT_BASE_URL = "https://my.aldimobile.com.au"
    LOGIN_PATH = "/login/"
    LOGIN_FORM_ACTION = %r{/login_check/?\z}
    SERVICE_SWITCH_PATH = %r{\A/admin/s/(?<id>\d+)/switch/?\z}
    MOBILE_NUMBER = /(?:\+?61[\s-]?|0)4(?:[\s-]?\d){8}/

    attr_reader :page

    def initialize(login:, password:, base_url: DEFAULT_BASE_URL, agent: nil)
      raise ConfigurationError, "login cannot be empty" if login.to_s.strip.empty?
      raise ConfigurationError, "password cannot be empty" if password.to_s.empty?

      @login = login.to_s
      @password = password.to_s
      @base_url = base_url.delete_suffix("/")
      @agent = agent || build_agent
      @authenticated = false
    end

    def authenticate!
      login_page = @agent.get("#{@base_url}#{LOGIN_PATH}")
      form = find_login_form(login_page)

      unless form
        raise UnexpectedResponseError, "ALDImobile login form was not found"
      end

      form["login_user[login]"] = @login
      form["login_user[password]"] = @password

      submit_button = form.button_with(name: "login_user[save]")
      @page = submit_button ? @agent.submit(form, submit_button) : form.submit

      unless authenticated_page?(@page)
        @authenticated = false
        raise AuthenticationError, authentication_error_message(@page)
      end

      @authenticated = true
      self
    rescue Mechanize::ResponseCodeError => error
      raise ConnectionError, "ALDImobile returned HTTP #{error.response_code}"
    rescue SocketError, Timeout::Error, EOFError, Errno::ECONNREFUSED,
      Errno::ECONNRESET, OpenSSL::SSL::SSLError => error
      raise ConnectionError, "Could not connect to ALDImobile: #{error.class}"
    end

    def authenticated?
      @authenticated
    end

    def services
      ensure_authenticated!

      @page.links.filter_map do |link|
        match = SERVICE_SWITCH_PATH.match(link.href.to_s)
        next unless match

        number = link.text.to_s[MOBILE_NUMBER]
        next unless number

        Service.new(
          id: match[:id],
          name: service_name(link.text, number),
          number: normalize_mobile_number(number)
        )
      end.uniq(&:id)
    end

    def service(identifier)
      ensure_authenticated!
      return identifier if identifier.is_a?(Service)

      query = identifier.to_s.strip
      matches = services.select do |candidate|
        candidate.id == query ||
          candidate.number == normalize_identifier_number(query) ||
          candidate.name.casecmp?(query)
      end

      if matches.empty?
        raise ServiceNotFoundError, "No ALDImobile service matches #{query.inspect}"
      end
      if matches.length > 1
        raise AmbiguousServiceError, "More than one ALDImobile service matches #{query.inspect}"
      end

      matches.first
    end

    def service_details(identifier)
      selected_service = service(identifier)
      overview = request { @agent.get("#{@base_url}/admin/s/#{selected_service.id}/switch") }
      roaming_enabled = roaming_enabled?(selected_service)

      Parsers::ServiceDetails.new.parse(
        page: overview,
        service: selected_service,
        roaming_enabled:
      )
    end

    def usage(identifier, from: Date.today - 30, to: Date.today)
      selected_service = service(identifier)
      from = coerce_date(from)
      to = coerce_date(to)
      raise ConfigurationError, "usage start date must not be after end date" if from > to

      page = request { @agent.get("#{@base_url}/admin/s/#{selected_service.id}/usage") }
      form = page.forms.find { |candidate| candidate.action.to_s.end_with?("/usage") }
      unless form
        raise UnexpectedResponseError, "ALDImobile usage form was not found"
      end

      form["usage[start]"] = from.iso8601
      form["usage[end]"] = to.iso8601
      submit_button = form.button_with(name: "usage[getusage]")
      result = request { submit_button ? @agent.submit(form, submit_button) : form.submit }

      Parsers::Usage.new.parse(page: result, service: selected_service, from:, to:)
    end

    def orders(identifier)
      selected_service = service(identifier)
      page = request { @agent.get("#{@base_url}/admin/s/#{selected_service.id}/orders") }
      Parsers::Orders.new.parse(page)
    end

    private

    def ensure_authenticated!
      raise AuthenticationError, "Log in before requesting services" unless authenticated?
    end

    def roaming_enabled?(selected_service)
      response = request do
        @agent.get("#{@base_url}/admin/roaming/status/#{selected_service.number}")
      end
      status = JSON.parse(response.body).fetch("roaming_status", nil)
      return true if status.to_s == "1"
      return false if status.to_s == "0"

      nil
    rescue JSON::ParserError
      nil
    end

    def request
      yield
    rescue Mechanize::ResponseCodeError => error
      raise ConnectionError, "ALDImobile returned HTTP #{error.response_code}"
    rescue SocketError, Timeout::Error, EOFError, Errno::ECONNREFUSED,
      Errno::ECONNRESET, OpenSSL::SSL::SSLError => error
      raise ConnectionError, "Could not connect to ALDImobile: #{error.class}"
    end

    def coerce_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ConfigurationError, "invalid ISO date: #{value.inspect}"
    end

    def build_agent
      Mechanize.new.tap do |agent|
        agent.user_agent = "sim_meter_au/#{VERSION} aldi_mobile"
        agent.open_timeout = 10
        agent.read_timeout = 30
      end
    end

    def find_login_form(login_page)
      return unless login_page.respond_to?(:form_with)

      login_page.form_with(id: "login-specific") ||
        login_page.form_with(action: LOGIN_FORM_ACTION)
    end

    def authenticated_page?(response_page)
      path = response_page.uri.path
      on_account_page = path == "/admin" || path.start_with?("/admin/")
      has_login_form = !find_login_form(response_page).nil?
      has_logout_link = !response_page.link_with(href: %r{/logout/?\z}).nil?

      !has_login_form && (on_account_page || has_logout_link)
    end

    def authentication_error_message(response_page)
      error_element = response_page.at(
        ".alert-danger, .form-error-message, .error, [role='alert']"
      )
      message = error_element&.text.to_s.gsub(/\s+/, " ").strip

      message.empty? ? "ALDImobile login failed" : message
    end

    def service_name(link_text, number)
      link_text.to_s.sub(number, "").sub(/\s*-\s*\z/, "").strip
    end

    def normalize_mobile_number(number)
      digits = number.gsub(/\D/, "")
      digits.start_with?("61") ? "0#{digits.delete_prefix("61")}" : digits
    end

    def normalize_identifier_number(identifier)
      digits = identifier.gsub(/\D/, "")
      return "" if digits.length < 9

      digits.start_with?("61") ? "0#{digits.delete_prefix("61")}" : digits
    end
    end
  end
end
