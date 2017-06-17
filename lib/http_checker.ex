defmodule FT.Health.HttpCall do
  @moduledoc "A checker that is healthy depending on the result of an HTTP request"

  @behaviour FT.Health.Checker

  alias FT.Health.Checker.Result

  @options [ssl: [{:versions, [:'tlsv1.2']}], recv_timeout: 2000, hackney: [pool: FT.Health]]

  @impl true
  def check(opts) do
    url = opts[:url] || raise ArgumentError, "#{__MODULE__} Need check :url"
    status_code = opts[:status_code] || 200
    headers = opts[:headers] || []
    method = opts[:method] || "GET"
    body = opts[:body] || ""
    poison_opts = (opts[:poison] || []) ++ @options

    result = HTTPoison.request(method, url, body, headers, poison_opts)

    case result do
      {:ok, %HTTPoison.Response{status_code: ^status_code}} ->
        Result.new(:ok, "OK")

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Result.new(:error, "Unexpected status code #{status_code}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        Result.new(:error, inspect reason)
    end
  end

end
