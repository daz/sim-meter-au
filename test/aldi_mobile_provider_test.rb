# frozen_string_literal: true

require "test_helper"

class AldiMobileProviderTest < Minitest::Test
  BASE_URL = "https://example.test"

  def test_logs_in_with_csrf_token_and_session_cookie
    stub_login_page

    login_request = stub_request(:post, "#{BASE_URL}/login_check")
      .with(
        headers: {"Cookie" => /PHPSESSID=test-session/},
        body: {
          "_csrf_token" => "csrf-token",
          "login_user" => {
            "login" => "0412345678",
            "password" => "secret-password",
            "save" => ""
          }
        }
      )
      .to_return(status: 302, headers: {"Location" => "/admin/"})

    stub_request(:get, "#{BASE_URL}/admin/")
      .to_return(status: 200, headers: html_headers, body: account_page)

    client = build_client

    assert_same client, client.authenticate!
    assert client.authenticated?
    assert_requested login_request, times: 1
  end

  def test_raises_an_authentication_error_without_exposing_credentials
    stub_login_page
    stub_request(:post, "#{BASE_URL}/login_check")
      .to_return(
        status: 200,
        headers: html_headers,
        body: login_page(error: "The login details are incorrect")
      )

    client = build_client
    error = assert_raises(SimMeterAU::AuthenticationError) { client.authenticate! }

    assert_equal "The login details are incorrect", error.message
    refute_includes error.message, "secret-password"
    refute client.authenticated?
  end

  def test_raises_when_the_login_form_is_missing
    stub_request(:get, "#{BASE_URL}/login/")
      .to_return(
        status: 200,
        headers: html_headers,
        body: "<html><body>Unavailable</body></html>"
      )

    error = assert_raises(SimMeterAU::UnexpectedResponseError) do
      build_client.authenticate!
    end

    assert_equal "ALDImobile login form was not found", error.message
  end

  def test_rejects_empty_credentials_before_connecting
    assert_raises(SimMeterAU::ConfigurationError) do
      build_client(login: "", password: "password")
    end

    assert_raises(SimMeterAU::ConfigurationError) do
      build_client(login: "0412345678", password: "")
    end
  end

  def test_lists_services_from_the_authenticated_account_page
    stub_login_page
    stub_request(:post, "#{BASE_URL}/login_check")
      .to_return(status: 302, headers: {"Location" => "/admin/s/overview"})
    stub_request(:get, "#{BASE_URL}/admin/s/overview")
      .to_return(status: 200, headers: html_headers, body: account_page_with_services)

    client = build_client
    client.authenticate!

    assert_equal [
      SimMeterAU::Service.new(id: "1234567", name: "Test SIM", number: "0400000001"),
      SimMeterAU::Service.new(id: "7654321", name: "Test Camera", number: "0400000002")
    ], client.services
  end

  def test_services_require_an_authenticated_session
    error = assert_raises(SimMeterAU::AuthenticationError) { build_client.services }

    assert_equal "Log in before requesting services", error.message
  end

  def test_finds_a_service_by_id_number_or_name
    stub_login_page
    stub_request(:post, "#{BASE_URL}/login_check")
      .to_return(status: 302, headers: {"Location" => "/admin/s/overview"})
    stub_request(:get, "#{BASE_URL}/admin/s/overview")
      .to_return(status: 200, headers: html_headers, body: account_page_with_services)
    client = build_client
    client.authenticate!

    assert_equal "1234567", client.service("1234567").id
    assert_equal "1234567", client.service("0400 000 001").id
    assert_equal "1234567", client.service("test sim").id
    assert_raises(SimMeterAU::ServiceNotFoundError) { client.service("missing") }
  end

  private

  def build_client(login: "0412345678", password: "secret-password")
    SimMeterAU.client(
      provider: :aldi_mobile,
      login:,
      password:,
      base_url: BASE_URL
    )
  end

  def stub_login_page
    stub_request(:get, "#{BASE_URL}/login/")
      .to_return(
        status: 200,
        headers: html_headers.merge(
          "Set-Cookie" => "PHPSESSID=test-session; Path=/; HttpOnly"
        ),
        body: login_page
      )
  end

  def html_headers
    {"Content-Type" => "text/html; charset=UTF-8"}
  end

  def login_page(error: nil)
    <<~HTML
      <!doctype html>
      <html>
        <body>
          #{%(<div class="alert-danger">#{error}</div>) if error}
          <form id="login-specific" method="post" action="/login_check">
            <input name="login_user[login]" type="text">
            <input name="login_user[password]" type="password">
            <input name="_csrf_token" type="hidden" value="csrf-token">
            <button name="login_user[save]" type="submit">Login</button>
          </form>
        </body>
      </html>
    HTML
  end

  def account_page
    <<~HTML
      <!doctype html>
      <html>
        <body>
          <main>My ALDImobile</main>
          <a href="/logout">Logout</a>
        </body>
      </html>
    HTML
  end


  def account_page_with_services
    <<~HTML
      <!doctype html>
      <html>
        <body>
          <a href="/admin/s/1234567/switch">Test SIM - 0400 000 001</a>
          <a href="/admin/s/7654321/switch">Test Camera - +61 400 000 002</a>
          <a href="/logout">Logout</a>
        </body>
      </html>
    HTML
  end
end
