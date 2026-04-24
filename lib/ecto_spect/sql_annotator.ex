defmodule EctoSpect.SqlAnnotator do
  @moduledoc """
  Injects caller information as SQL comments in dev/test environments.

  Add to your `Repo` module to see which Elixir code generated each query:

      if Mix.env() in [:dev, :test] do
        @impl true
        def default_options(_op), do: [stacktrace: true]

        @impl true
        def prepare_query(_op, query, opts) do
          comment = EctoSpect.SqlAnnotator.build_comment(opts)
          {query, [comment: comment, prepare: :unnamed] ++ opts}
        end
      end

  ## Why `prepare: :unnamed`?

  Each unique comment string produces a distinct prepared statement key.
  Without `prepare: :unnamed`, PostgreSQL would cache the first plan seen
  for each SQL template and return the wrong plan for different callers.
  `:unnamed` tells Postgrex to use the "simple" query protocol, avoiding
  plan cache pollution.

  ## Output

  Queries in your logs will look like:

      -- ecto_spect: lib/my_app/accounts.ex:42 MyApp.Accounts.list_users/0
      SELECT u0."id", u0."email" FROM "users" AS u0

  This makes it trivial to find which function caused a slow query in
  development logs or in database query logs (`log_min_duration_statement`).
  """

  @doc """
  Build a SQL comment string from the stacktrace in `opts`.

  Returns an empty string if no useful caller is found, so the query
  is sent without a comment rather than failing.
  """
  @spec build_comment(keyword()) :: String.t()
  def build_comment(opts) do
    case Keyword.get(opts, :stacktrace) do
      nil -> ""
      [] -> ""
      stacktrace -> "/* ecto_spect: #{extract_caller(stacktrace)} */"
    end
  end

  # Find the first frame that is application code (not Ecto/Elixir internals).
  defp extract_caller(stacktrace) do
    stacktrace
    |> Enum.find(fn
      {mod, _fun, _arity, info} ->
        mod_str = Atom.to_string(mod)
        has_file = Keyword.has_key?(info, :file)

        has_file and
          not String.starts_with?(mod_str, "Elixir.Ecto") and
          not String.starts_with?(mod_str, "Elixir.DBConnection") and
          not String.starts_with?(mod_str, "Elixir.Postgrex") and
          not String.starts_with?(mod_str, "Elixir.EctoSpect")

      _ ->
        false
    end)
    |> case do
      {mod, fun, arity, info} ->
        file = info |> Keyword.get(:file, "unknown") |> to_string()
        line = Keyword.get(info, :line, 0)
        "#{file}:#{line} #{inspect(mod)}.#{fun}/#{arity}"

      nil ->
        "unknown"
    end
  end
end
