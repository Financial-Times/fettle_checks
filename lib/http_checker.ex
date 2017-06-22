defmodule Fettle.HttpCheckerBase do
  @moduledoc """
  Base module for defining `Fettle.Checker` modules based on an HTTP call.

  See `Fettle.HttpChecker` for details.
  """

  @callback compare_response(response :: HTTPPoison.Response.t, opts :: Keyword.t) :: Result.t
  @callback compare_resp_body(content_type :: String.t, body :: String.t, expected :: any, opts :: Keyword.t) :: Result.t
  @optional_callbacks compare_response: 2, compare_resp_body: 4

  @doc "Get a header from a keyword-like list (but with string keys)."
  @spec get_header(headers :: [{String.t, String.t}], key :: String.t) :: String.t | nil
  def get_header(headers, key) when is_list(headers) do
    case :lists.keyfind(key, 1, headers) do
      {_, content_type} -> content_type
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

      @options [ssl: [{:versions, [:'tlsv1.2']}], recv_timeout: 2000, hackney: [pool: Fettle.Checker]]

      @doc "compare the HTTP response and compute a `Fettle.Checker.Result`"
      @spec compare_response(resp :: HTTPoison.Response.t, opts :: Keyword.t) :: Result.t
      def compare_response(response, opts)

      def compare_response(resp = %HTTPoison.Response{status_code: status_code}, opts) do
        expected_status = opts[:status_code] || 200

        case Fettle.HttpCheckerBase.expected_status_code?(status_code, expected_status) do
          true ->
            run_compare_response_body(opts[:resp_body], resp, opts)
          false ->
            Result.error("Unexpected status code #{status_code}.")
        end
      end

      @doc "choses the method used to compare the response body and executes it"
      @spec run_compare_response_body(resp_body_opt :: any, resp :: HTTPoison.Response.t, opts :: Keyword.t) :: Result.t
      def run_compare_response_body(resp_body_opt, resp, opts)

      def run_compare_response_body(nil, _resp, _opts), do: Result.ok()
      def run_compare_response_body(false, _resp, _opts), do: Result.ok()
      def run_compare_response_body(fun, %HTTPoison.Response{headers: headers, body: body}, opts) when is_function(fun, 3) do
        content_type = Fettle.HttpCheckerBase.get_header(headers, "content-type")
        fun.(content_type, body, opts)
      end
      def run_compare_response_body({mod, fun}, %HTTPoison.Response{headers: headers, body: body}, opts) when is_atom(mod) and is_atom(fun) do
        content_type = Fettle.HttpCheckerBase.get_header(headers, "content-type")
        apply(mod, fun, [content_type, body, opts])
      end
      def run_compare_response_body(expected_body, %HTTPoison.Response{headers: headers, body: body}, opts) do
        content_type = Fettle.HttpCheckerBase.get_header(headers, "content-type")
        compare_resp_body(content_type, body, expected_body, opts)
      end

      @doc """
      Compare the response body with to an expected content-type, body or pattern and compute a `Fettle.Checker.Response`.

      Supported types for `expected_body` are: `String` or `Regex`, extensions of this module may implement others.
      """
      @spec compare_resp_body(content_type :: String.t, body :: String.t, expected_body :: any, opts :: Keyword.t) :: Result.t
      def compare_resp_body(content_type, body, expected_body, opts)

      def compare_resp_body(_, body, expected_body, _opts) when is_binary(body) and is_binary(expected_body) do
        case String.equivalent?(body, expected_body) do
          true -> Result.ok()
          false -> Result.error("Unexpected response body.")
        end
      end

      def compare_resp_body(_, body, regex = %Regex{}, _opts) when is_binary(body) do
        case Regex.match?(regex, body) do
          true -> Result.ok()
          false -> Result.error("Unexpected response body.")
        end
      end

      @doc "Call an HTTP(S) end-point and assert a response code/response body and return a `Fettle.Checker.Response`"
      @impl true
      def check(opts) do
        url = opts[:url] || raise ArgumentError, "#{__MODULE__} Need check :url"
        headers = opts[:headers] || []
        method = opts[:method] || "GET"
        req_body = opts[:req_body] || ""
        status_code = opts[:status_code] || 200
        poison_opts = (opts[:poison] || []) ++ @options

        result = HTTPoison.request(method, url, req_body, headers, poison_opts)

        case result do
          {:ok, resp = %HTTPoison.Response{}} ->
            compare_response(resp, opts)

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
    },
    Fettle.HttpChecker,
    [url: "http://my-service.com/endpoint", method: "POST", req_body: body(), status_code: 200..202, resp_body: ~r/.*xy??y.*/]
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

  ## Specifying the response body

  The supported values for `resp_body` are:
    * `String` - exact value of body (comparison via `String.equivalent?/2`).
    * `Regex` - a regex to use to match the body.
    *  `function/3` - called passing content-type header, body and options; returning `Fettle.Checker.Result`.
    * `{module, function}` - called passing content-type header, body and options; returning `Fettle.Checker.Result`.

  Simple customization can be performed by using the function or module `resp_body` options.

  ## Customizing via Fettle.HttpCheckerBase

  Note that the `check/1`, `compare_response/2` and `compare_resp_body/4` functions are all overridable
  so that this module can be used as a base for more custom implementations; indeed `Fettle.HttpChecker` itself
  is just a default implementation of `Fettle.HttpCheckerBase`.

  e.g.
  ```
  defmodule MyResponseChecker do
    use Fettle.HttpCheckerBase

    def compare_response(resp = %HTTPoison.Response{}, opts) do
      # your implementation
    end
  end
  ```

  `compare_response/2` is called from `check/1`, and checks the status code matches, before calling `compare_resp_body/4` if
  the `resp_body` option is given, so you can override at either the request or body level.

  Note that if you are overriding only `compare_resp_body/4`, you *must* provide a value for the `resp_body` option,
  else it will be skipped by the default implementation of `compare_response/2`. You can do this robustly by also
  overriding `check/1` to pass a truthy value and calling `super`:

  ```
  defmodule JsonBodyChecker do
    use Fettle.HttpCheckerBase
    def check(opts), do: super([{:resp_body, true} | opts])
    def compare_resp_body("application/json", body, true, opts) do
      # your implementation
    end
  end

  The `checker/1` argument `opts` are all passed through to the lower-level functions, so you can add your own.
  """

  use Fettle.HttpCheckerBase
end
