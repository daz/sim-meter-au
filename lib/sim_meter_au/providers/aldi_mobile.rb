# frozen_string_literal: true

require "net/http"
require "openssl"
require "json"
require "date"
require "securerandom"

module SimMeterAU
  module Providers
    class AldiMobile < Provider
      provider_key :aldi_mobile
      display_name "ALDImobile"
      credential_names :login, :password

      DEFAULT_BASE_URL = "https://skyhigh-api.symbio.global/dx-sync"
      APP_ID = "8b1a2963-3c28-35b4-9c9a-8a15ffc8dea2"
      TENANCY_ID = "SP_ALDIMOBILE_AUS"
      PAGE_SIZE = 100

      def initialize(login:, password:, base_url: DEFAULT_BASE_URL, http: Net::HTTP)
        raise ConfigurationError, "login cannot be empty" if login.to_s.strip.empty?
        raise ConfigurationError, "password cannot be empty" if password.to_s.empty?

        @login = login.to_s.gsub(/\s+/, "")
        @password = password.to_s
        @base_url = base_url.delete_suffix("/")
        @http = http
      end

      def authenticate!
        clear_session
        mobile = @login.match?(/\A(?:04|\+?614)/)
        result = request(:post, "/crm/v1/login", "customerLogin",
          headers: {"appId" => APP_ID, "type" => mobile ? "msisdn" : "accountNo"},
          body: {username: mobile ? international_number(@login) : @login,
                 password: @password, source: "app"})
        require_hash(result)
        if [true, "true", 1, "1"].include?(result["isPasswordExpired"])
          raise AuthenticationError, "ALDImobile requires a password update; sign in to My ALDI Mobile"
        end
        @account_token = access_token(result)
        profile = request(:get, "/crm/v1/profile", "profile", token: @account_token)
        require_hash(profile)
        list = profile["serviceList"]
        unless list.is_a?(Array) && list.all? { |item| item.is_a?(Hash) }
          raise UnexpectedResponseError, "ALDImobile service list was not found"
        end
        @services = list.filter_map do |item|
          next if item["msisdn"].to_s.empty? || item["serviceAccountNo"].to_s.empty?

          Service.new(id: item["serviceAccountNo"].to_s,
            name: item["servicename"].to_s, number: local_number(item["msisdn"]))
        end.uniq(&:id).freeze
        self
      rescue Error
        clear_session
        raise
      end

      def authenticated?
        !@account_token.nil? && !@services.nil?
      end

      def services
        ensure_authenticated!
        @services.dup
      end

      def service(identifier)
        query = identifier.is_a?(Service) ? identifier.id : identifier.to_s.strip
        matches = services.select do |candidate|
          candidate.id == query || candidate.number == local_number(query) ||
            candidate.name.casecmp?(query)
        end
        raise ServiceNotFoundError, "No ALDImobile service matches #{query.inspect}" if matches.empty?
        if matches.length > 1
          raise AmbiguousServiceError, "More than one ALDImobile service matches #{query.inspect}"
        end

        matches.first
      end

      def service_details(identifier)
        selected = service(identifier)
        token = service_token(selected)
        details = request(:get, "/crm/v1/fetch/currentPlanDetails", "getCurrentPlanDetails", token:)
        profile = request(:get, "/crm/v1/profile", "profile", token:)
        require_hash(profile)
        ir_services = profile["irServices"]
        roaming = ir_services.first["selfcare_ir_status"] if ir_services.is_a?(Array) && ir_services.first.is_a?(Hash)
        roaming_enabled = {"Enable" => true, "Disable" => false}[roaming]
        Parsers::Api.new.service_details(details, service: selected, roaming_enabled:)
      end

      def usage(identifier, from: Date.today - 30, to: Date.today)
        from = coerce_date(from)
        to = coerce_date(to)
        raise ConfigurationError, "usage start date must not be after end date" if from > to
        raise ConfigurationError, "usage date range cannot exceed 366 days" if to - from > 366

        selected = service(identifier)
        token = service_token(selected)
        params = {start: from.strftime("%m-%d-%Y"), end: to.strftime("%m-%d-%Y")}
        summary = request(:get, "/usage/v1/Usagesummary", "getUsageSummary", token:, params:)
        parser = Parsers::Api.new
        records = %w[Call SMS Data].flat_map do |category|
          paginate do |page|
            result = request(:get, "/usage/v1/Usagedetails", "getUsageDetails", token:,
              params: params.merge(usageType: "ALL", category:, size: PAGE_SIZE, page:))
            require_hash(result)
            [parser.usage_records(result, service: selected), result["totalRecords"]]
          end
        end
        UsageReport.new(service: selected, from:, to:,
          summaries: parser.usage_summaries(summary), records:)
      end

      def orders(identifier)
        selected = service(identifier)
        token = service_token(selected)
        parser = Parsers::Api.new
        paginate do |page|
          result = request(:get, "/crm/v1/getSalesOrders", "getSalesOrders", token:,
            params: {pageNo: page, noOfRecords: PAGE_SIZE})
          require_hash(result)
          [parser.orders(result, service: selected), result["totalRecords"]]
        end
      end

      private

      def clear_session
        @account_token = @services = nil
      end

      def ensure_authenticated!
        raise AuthenticationError, "Log in before requesting services" unless authenticated?
      end

      def service_token(selected)
        # Tenant/app headers invoke password authentication, rather than service switching.
        result = request(:post, "/crm/v1/login", "customerLogin", tenant: false,
          token: @account_token, headers: {"type" => "msisdn"},
          body: {username: international_number(selected.number), password: nil,
                 source: "app", accountNo: selected.id})
        require_hash(result)
        primary = result["primaryDevice"]
        unless primary.is_a?(Hash) && primary["accountNo"].to_s == selected.id
          raise UnexpectedResponseError, "ALDImobile returned a different SIM after switching services"
        end
        access_token(result)
      end

      def request(method, path, operation, body: nil, params: {}, headers: {}, tenant: true, token: nil)
        uri = URI("#{@base_url}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?
        http_request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
        request_headers = {
          "Accept" => "application/json", "Content-Type" => "application/json;charset=UTF-8",
          "source" => "Selfcare", "destination" => "CrmServices", "operation" => operation,
          "correlationId" => SecureRandom.uuid, "srDate" => (Time.now.to_f * 1000).to_i.to_s,
          "User-Agent" => "sim_meter_au/#{VERSION} aldi_mobile"
        }
        request_headers["tenancyId"] = TENANCY_ID if tenant
        request_headers["token"] = token if token
        request_headers.merge(headers).each { |key, value| http_request[key] = value }
        http_request.body = JSON.generate(body) if body
        response = @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: 10, read_timeout: 30) { |http| http.request(http_request) }
        status = response.code.to_i
        if status >= 500 || [408, 429].include?(status)
          raise ConnectionError, "ALDImobile returned HTTP #{status}"
        end
        if [401, 403].include?(status)
          clear_session
          raise AuthenticationError, "ALDImobile rejected authentication (HTTP #{status})"
        end
        unless status.between?(200, 299)
          raise UnexpectedResponseError, "ALDImobile returned HTTP #{status}"
        end
        payload = JSON.parse(response.body)
        envelope = payload["response"] if payload.is_a?(Hash)
        unless envelope.is_a?(Hash) && envelope.key?("result")
          raise UnexpectedResponseError, "ALDImobile returned an unexpected API response"
        end
        unless [true, "true"].include?(envelope["success"])
          result = envelope["result"]
          arguments = result["arguments"] if result.is_a?(Hash)
          code = arguments["statusCode"].to_i if arguments.is_a?(Hash)
          code = status if code.nil? || code.zero?
          error_class = if code >= 500 || [408, 429].include?(code)
            ConnectionError
          elsif [401, 403].include?(code) || operation == "customerLogin"
            AuthenticationError
          else
            UnexpectedResponseError
          end
          clear_session if error_class == AuthenticationError
          raise error_class, "ALDImobile #{operation} failed (status #{code})"
        end
        envelope["result"]
      rescue JSON::ParserError
        raise UnexpectedResponseError, "ALDImobile returned invalid JSON"
      rescue SocketError, Timeout::Error, EOFError, IOError, Errno::ECONNREFUSED,
        Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, OpenSSL::SSL::SSLError => error
        raise ConnectionError, "Could not connect to ALDImobile: #{error.class}"
      end

      def require_hash(result)
        raise UnexpectedResponseError, "ALDImobile returned an unexpected API result" unless result.is_a?(Hash)
      end

      def access_token(result)
        token = result["accessToken"]
        unless token.is_a?(String) && !token.empty?
          raise UnexpectedResponseError, "ALDImobile did not return an access token"
        end
        token
      end

      def paginate
        records = []
        page = 1
        loop do
          items, total = yield page
          total = Integer(total)
          if total.negative? || (items.empty? && records.length < total)
            raise UnexpectedResponseError, "ALDImobile returned incomplete pagination"
          end
          records.concat(items)
          break if records.length >= total
          raise UnexpectedResponseError, "ALDImobile pagination limit exceeded" if page >= 10_000
          page += 1
        end
        records
      rescue ArgumentError, TypeError
        raise UnexpectedResponseError, "ALDImobile returned an invalid record count"
      end

      def coerce_date(value)
        return value if value.is_a?(Date)
        Date.iso8601(value.to_s)
      rescue Date::Error
        raise ConfigurationError, "invalid ISO date: #{value.inspect}"
      end

      def local_number(value)
        value.to_s.gsub(/\D/, "").sub(/\A61/, "0")
      end

      def international_number(value)
        local_number(value).sub(/\A0/, "61")
      end
    end
  end
end
