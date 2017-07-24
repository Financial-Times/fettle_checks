defmodule Fettle.HttpCheckerBase do
  @moduledoc """
  Base module for defining `Fettle.Checker` modules based on an HTTP call.

  See `Fettle.HttpChecker` for details.
  """

  @callback compare_response(response :: HTTPPoison.Response.t, config :: map) :: Result.t
  @callback compare_resp_body(content_type :: String.t, body :: String.t, expected :: any, config :: map) :: Result.t
  @optional_callbacks compare_response: 2, compare_resp_body: 4

  @doc "Get a header from a keyword-like list (but with string keys), returning header value or `nil` if not found."
  @spec get_header(headers :: [{String.t, String.t}], key :: String.t) :: String.t | nil
  def get_header(headers, key) when is_list(headers) do
    case :lists.keyfind(key, 1, headers) do
      {_, value} -> value
      false -> nil
    end
  end

  @typedoc "ways of specifing a status code"
  @type status_code_spec :: non_neg_integer | Range.t

  @doc "test a status code against a range, value or list of range or value"
  @spec expected_status_code?(status_code :: non_neg_integer, expected :: status_code_spec | [status_code_spec]) :: boolean
  def expected_status_code?(status_code, expected_spec) when is_integer(status_code) do
    case expected_spec do
      range = %Range{} -> status_code in range
      code when is_integer(code) -> status_code == code
      [spec | specs] -> expected_status_code?(status_code, spec) || expected_status_code?(status_code, specs)
      [] -> false
    end
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Fettle.Checker
      @behaviour Fettle.HttpCheckerBase

      alias Fettle.Checker.Result

      @poison_options ssl: [{:versions, [:'tlsv1.2']}], recv_timeout: 2000, hackney: [pool: Fettle.Checker]

      @doc "compare the HTTP response and compute a `Fettle.Checker.Result`"
      @spec compare_response(resp :: HTTPoison.Response.t, config :: map) :: Result.t
      def compare_response(response, config)

      def compare_response(resp = %HTTPoison.Response{status_code: status_code}, config) do
        expected_status = config.status_code

        case Fettle.HttpCheckerBase.expected_status_code?(status_code, expected_status) do
          true ->
            run_compare_response_body(config.resp_body, resp, config)
          false ->
            Result.error("Unexpected status code #{status_code}.")
        end
      end

      @doc "choses the method used to compare the response body and executes it"
      @spec run_compare_response_body(resp_body_opt :: any, resp :: HTTPoison.Response.t, config :: map) :: Result.t
      def run_compare_response_body(resp_body_opt, resp, config)

      def run_compare_response_body(nil, _resp, _config), do: Result.ok()
      def run_compare_response_body(false, _resp, _config), do: Result.ok()
      def run_compare_response_body(fun, %HTTPoison.Response{headers: headers, body: body}, config) when is_function(fun, 3) do
        content_type = Fettle.HttpCheckerBase.get_header(headers, "content-type")
        fun.(content_type, body, config)
      end
      def run_compare_response_body({mod, fun}, %HTTPoison.Response{headers: headers, body: body}, config) when is_atom(mod) and is_atom(fun) do
        content_type = Fettle.HttpCheckerBase.get_header(headers, "content-type")
        apply(mod, fun, [content_type, body, config])
      end
      def run_compare_response_body(expected_body, %HTTPoison.Response{headers: headers, body: body}, config) do
        content_type = Fettle.HttpCheckerBase.get_header(headers, "content-type")
        compare_resp_body(content_type, body, expected_body, config)
      end

      @doc """
      Compare the response body with to an expected content-type, body or pattern and compute a `Fettle.Checker.Response`.

      Supported types for `expected_body` are: `String` or `Regex`, extensions of this module may implement others.
      """
      @spec compare_resp_body(content_type :: String.t, body :: String.t, expected_body :: any, config :: map) :: Result.t
      def compare_resp_body(content_type, body, expected_body, config)

      def compare_resp_body(_, body, expected_body, _config) when is_binary(body) and is_binary(expected_body) do
        case String.equivalent?(body, expected_body) do
          true -> Result.ok()
          false -> Result.error("Unexpected response body.")
        end
      end

      def compare_resp_body(_, body, regex = %Regex{}, _config) when is_binary(body) do
        case Regex.match?(regex, body) do
          true -> Result.ok()
          false -> Result.error("Unexpected response body.")
        end
      end

      @doc "add `user-agent` header, if not present"
      def default_headers(headers) do
        case Fettle.HttpCheckerBase.get_header(headers, "user-agent") do
          nil ->
            system_code = Application.get_env(:fettle, :system_code, "fettle")
            [{"user-agent", system_code} | headers]
          _ -> headers
        end
      end

      @doc "check options and transform into a map, applying defaults as necessary"
      def init(opts) do
        opts[:url] || raise ArgumentError, "#{__MODULE__} Need check :url"

        config = Enum.into(opts, %{headers: [], method: "GET", req_body: "", status_code: 200, poison: [], resp_body: nil})

        headers = default_headers(config.headers)

        %{config | poison: config.poison ++ @poison_options, headers: headers}
      end

      @doc "Call an HTTP(S) end-point and assert a response code/response body and return a `Fettle.Checker.Response`"
      @impl true
      def check(config = %{method: method, url: url, req_body: req_body, headers: headers, poison: poison_opts}) do

        result = HTTPoison.request(method, url, req_body, headers, poison_opts)

        case result do
          {:ok, resp = %HTTPoison.Response{}} ->
            compare_response(resp, config)

          {:error, %HTTPoison.Error{reason: reason}} ->
            Result.error(inspect reason)
        end
      end

      defoverridable Module.definitions_in(__MODULE__)
    end
  end
end

defmodule Fettle.HttpChecker do
  @moduledoc ~S"""
  A `Fettle.Checker` that is healthy depending on the result of an HTTP request.

  Implements the `Fettle.Checker` behaviour.

  Configure in Fettle health-check config as e.g.:

  ```elixir
  {
    %{
      name: "my-service-check",
      panic_guide_url: "...",
      ...
      checker: Fettle.HttpChecker,
      args: [url: "http://my-service.com/endpoint", method: "POST", req_body: body(), status_code: 200..202, resp_body: ~r/.*xy??y.*/]
    },
  }
  ```

  ## Options

  | Key | Type | Description | Required/default |
  | --- | ---- | ----------- | ---------------- |
  | `url` | `String.t` | URL to call | required |
  | `headers` | `{String.t, String.t}` | Headers to pass to request | `[]` |
  | `method` | `String.t` | HTTP method | `"GET"`  |
  | `req_body` | `String.t` | Body to send with POST, PUT | `""` |
  | `poison` | `list` | Additional options for `HTTPoison.request/5` | `[]` |
  | `status_code` | `non_neg_integer \| Range.t \| [non_neg_integer \| Range.t]` | Status code to match | `200` |
  | `resp_body` | any | Expected response body | `false` (don't care) |

  ## Specifying the expected response body

  The supported values for `resp_body` are:
    * `String` - exact value of body (comparison via `String.equivalent?/2`).
    * `Regex` - a regex to use to match the body.
    *  `function/3` - called passing content-type header, body and options map; returning `Fettle.Checker.Result`.
    * `{module, function}` - called passing content-type header, body and options map; returning `Fettle.Checker.Result`.

  Simple customization can be performed by using the function or module `resp_body` options.

  ## Customizing via Fettle.HttpCheckerBase

  Note that the `check/1`, `compare_response/2` and `compare_resp_body/4` functions are all overridable
  so that this module can be used as a base for more custom implementations; indeed `Fettle.HttpChecker` itself
  is just a default implementation of `Fettle.HttpCheckerBase`.

  e.g.
  ```
  defmodule MyResponseChecker do
    use Fettle.HttpCheckerBase

    def compare_response(resp = %HTTPoison.Response{}, config) do
      # your implementation
    end
  end
  ```

  `compare_response/2` is called from `check/1`, and checks the status code matches, before calling `compare_resp_body/4` if
  the `resp_body` option is given, so you can override at either the request or body level.

  Note that if you are overriding only `compare_resp_body/4`, you *must* provide a value for the `resp_body` option,
  else it will be skipped by the default implementation of `compare_response/2`. You can do this robustly by also
  overriding `init/1` to pass a truthy value for the `resp_body` opt, and calling `super`:

  ```
  defmodule JsonBodyChecker do
    use Fettle.HttpCheckerBase
    def init(opts), do: super([{:resp_body, true} | opts])
    def compare_resp_body("application/json", body, true, config) do
      # your implementation
    end
  end

  The result of the `init/1` function is a map with all keys from the `opts` argument; this is passed through to the lower-level functions
  as `config`, so you can add your own parameters for these functions.
  """

  use Fettle.HttpCheckerBase
end
