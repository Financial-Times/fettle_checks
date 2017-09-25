defmodule HttpCheckerTest do
  use ExUnit.Case

  alias Fettle.Checker.Result

  defmodule Router do
    use Plug.Router

    plug :match
    plug :dispatch

    get "/test" do
      conn
      |> put_resp_header("content-type", "text/plain")
      |> send_resp(200, "GET OK")
    end

    get "/test/json" do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(200, ~S({"GET": "OK"}))
    end


    post "/test" do
      conn
      |> put_resp_header("content-type", "text/plain")
      |> send_resp(200, "POST OK")
    end

    get "/error" do
      conn
      |> put_resp_header("content-type", "text/plain")
      |> send_resp(401, "GET DENIED")
    end

    post "/error" do
      conn
      |> put_resp_header("content-type", "text/plain")
      |> send_resp(401, "POST DENIED")
    end

    match _ do
      send_resp(conn, 404, "oops")
    end

  end

  setup do
    Application.ensure_all_started(:cowboy)
    Application.ensure_all_started(:plug)
    Application.ensure_all_started(:hackney)

    Plug.Adapters.Cowboy.http __MODULE__.Router, []

    :ok
  end

  test "missing required opts" do
    assert_raise ArgumentError, fn -> Fettle.HttpChecker.init(x: "http://localhost:4000/test") end
  end

  test "user agent added to headers if not present" do
    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", headers: [{"x-api-key", "foo"}])
    assert {"user-agent", "fettle_checks"} in config.headers
  end

  test "user agent not added to headers if already present" do
    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", headers: [{"x-api-key", "foo"}, {"user-agent", "my-agent"}])
    assert {"user-agent", "my-agent"} in config.headers
    refute {"user-agent", "fettle_checks"} in config.headers
  end

  test "merge poison opts" do
    opts = Fettle.HttpChecker.default_httpoison_opts([])
    assert opts[:hackney] == [pool: Fettle.Checker, timeout: 10_000]
    assert opts[:recv_timeout] == 2000

    opts = Fettle.HttpChecker.default_httpoison_opts([recv_timeout: 5000, hackney: [timeout: 2000]])
    assert opts[:hackney] == [pool: Fettle.Checker, timeout: 2000]
    assert opts[:recv_timeout] == 5000
  end

  test "successful check with all defaults" do

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test")
    result = Fettle.HttpChecker.check(config)

    assert %Result{status: :ok} = result

  end

  test "expected_status_code?" do
    assert Fettle.HttpCheckerBase.expected_status_code?(200, 200) == true
    assert Fettle.HttpCheckerBase.expected_status_code?(201, 200) == false

    assert Fettle.HttpCheckerBase.expected_status_code?(200, [200, 201]) == true
    assert Fettle.HttpCheckerBase.expected_status_code?(201, [200, 202]) == false

    assert Fettle.HttpCheckerBase.expected_status_code?(200, 200..202) == true
    assert Fettle.HttpCheckerBase.expected_status_code?(203, 200..202) == false

    assert Fettle.HttpCheckerBase.expected_status_code?(200, [200..201, 203..204]) == true
    assert Fettle.HttpCheckerBase.expected_status_code?(202, [200..201, 203..204]) == false

    assert Fettle.HttpCheckerBase.expected_status_code?(204, [200, 203..204]) == true
    assert Fettle.HttpCheckerBase.expected_status_code?(205, [200..202, 205]) == true
  end

  test "using status code" do

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", status_code: 200)
    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :ok} = result

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", status_code: 201)
    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :error, message: "Unexpected status code 200."} = result

  end

  test "using regex body match" do

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body: ~r/.*OK.*/)
    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :ok} = result

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body: ~r/.*NOK.*/)
    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :error, message: "Unexpected response body."} = result

  end

  test "using exact body match" do

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body: "GET OK")
    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :ok} = result

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body: "GET NOK")
    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :error, message: "Unexpected response body."} = result

  end

  test "using fun body match" do
    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body:
      fn(_type, body, _opts) ->
        case body do
          "GET OK" -> Result.ok("Match.")
          _ -> Result.error("No Match.")
        end
      end
    )

    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :ok, message: "Match."} = result

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body:
      fn(_type, body, _opts) ->
        case body do
          "GET OK" -> Result.error("No Match.")
          _ -> Result.ok()
        end
      end
    )

    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :error, message: "No Match."} = result

  end

  test "using {mod, fun} body match" do
    defmodule Mod do
      def doit(_type, body, opts) do
        match = opts[:xmatch]
        case body do
          ^match -> Result.ok("Match.")
          _ -> Result.error("No Match.")
        end
      end
    end


    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body: {Mod, :doit}, xmatch: "GET OK")

    result = Fettle.HttpChecker.check(config)

    assert %Result{status: :ok, message: "Match."} = result

    config = Fettle.HttpChecker.init(url: "http://localhost:4000/test", resp_body: {Mod, :doit}, xmatch: "NOK")

    result = Fettle.HttpChecker.check(config)
    assert %Result{status: :error, message: "No Match."} = result
  end

  describe "custom implementations using HttpCheckerBase" do

    test "override compare_response" do
      defmodule CustomChecker.CompareResponse do
        use Fettle.HttpCheckerBase

        def compare_response(_response, _opts) do
          Result.warn("WARN")
        end
      end

      config = CustomChecker.CompareResponse.init(url: "http://localhost:4000/test")
      result = CustomChecker.CompareResponse.check(config)

      assert %Result{status: :warn} = result
    end


    test "override compare_resp_body" do
      defmodule CustomChecker.CompareRespBody do
        @moduledoc false
        use Fettle.HttpCheckerBase

        def init(opts) do
          super([{:resp_body, true} | opts]) # ensure that compare_resp_body/4 is called
        end

        # def check(opts) do
        #   super([{:resp_body, true} | opts]) # ensure that compare_resp_body/4 is called
        # end

        def compare_resp_body("application/json", _body, _expected, _opts) do
          Result.ok("JSON")
        end

        def compare_resp_body(_, _body, _expected, _opts) do
          Result.warn("NOT JSON")
        end

      end

      config = CustomChecker.CompareRespBody.init(url: "http://localhost:4000/test")
      result = CustomChecker.CompareRespBody.check(config)
      assert %Result{status: :warn, message: "NOT JSON"} = result

      config = CustomChecker.CompareRespBody.init(url: "http://localhost:4000/test/json")
      result = CustomChecker.CompareRespBody.check(config)
      assert %Result{status: :ok, message: "JSON"} = result
    end
  end
end
