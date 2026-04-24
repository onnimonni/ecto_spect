defmodule EctoSpect.ExplainRunner do
  @compile {:no_warn_undefined, Postgrex}

  @moduledoc """
  Runs EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) on captured queries using a
  dedicated Postgrex connection that is separate from the Ecto sandbox.

  Using a separate connection avoids sandbox ownership conflicts because EXPLAIN
  is read-only from the test data perspective. For mutation queries (INSERT,
  UPDATE, DELETE), EXPLAIN is wrapped in a rolled-back transaction so no data
  is actually modified.

  One connection is opened per test module (via `setup_all` in `EctoSpect.Case`)
  and closed when the module finishes.
  """

  require Logger

  @explain_select_prefix "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) "
  @explain_mutation_prefix "EXPLAIN (FORMAT JSON) "

  @doc """
  Open a dedicated Postgrex connection for EXPLAIN queries.

  Strips pool/sandbox configuration from the repo config so we get a plain
  connection to the database server.
  """
  @spec open_connection(module()) :: {:ok, pid()} | {:error, term()}
  def open_connection(repo) do
    pg_config =
      repo.config()
      |> Keyword.take([:hostname, :port, :database, :username, :password, :ssl, :ssl_opts])
      |> Keyword.put(:name, nil)
      |> Keyword.put(:pool_size, 1)

    Postgrex.start_link(pg_config)
  end

  @doc """
  Close a connection opened by `open_connection/1`.
  """
  @spec close_connection(pid()) :: :ok
  def close_connection(conn) do
    GenServer.stop(conn)
  end

  @doc """
  Run EXPLAIN on a single captured entry, parse the plan, and return violations
  from all EXPLAIN-based rules.
  """
  @spec explain_entry(pid(), map(), EctoSpect.Config.t()) :: [EctoSpect.Violation.t()]
  def explain_entry(conn, entry, config) do
    case run_explain(conn, entry) do
      {:ok, plan_json} ->
        nodes = EctoSpect.PlanParser.parse(plan_json)
        run_plan_rules(nodes, entry, config)

      {:error, reason} ->
        Logger.warning("[EctoSpect] EXPLAIN failed for query: #{inspect(reason)}\n#{entry.sql}")
        []
    end
  end

  @doc """
  Run EXPLAIN on all entries for a test and return all violations.
  """
  @spec explain_all(pid(), [map()], EctoSpect.Config.t()) :: [EctoSpect.Violation.t()]
  def explain_all(conn, entries, config) do
    Enum.flat_map(entries, &explain_entry(conn, &1, config))
  end

  # Run the actual EXPLAIN query. Wraps mutations in a rolled-back transaction.
  defp run_explain(conn, entry) do
    prefix = if mutation?(entry.sql), do: @explain_mutation_prefix, else: @explain_select_prefix
    sql = prefix <> entry.sql
    params = entry.params

    if mutation?(entry.sql) do
      explain_mutation(conn, sql, params)
    else
      case Postgrex.query(conn, sql, params) do
        {:ok, %{rows: [[result]]}} ->
          {:ok, decode_plan(result)}

        {:error, _} = err ->
          err
      end
    end
  end

  # For mutations, wrap in a transaction and roll back so no data is changed.
  defp explain_mutation(conn, sql, params) do
    Postgrex.transaction(conn, fn tx_conn ->
      try do
        result = Postgrex.query!(tx_conn, sql, params)
        Postgrex.rollback(tx_conn, {:explain_done, result})
      rescue
        e -> Postgrex.rollback(tx_conn, {:explain_error, e})
      end
    end)
    |> case do
      {:error, {:explain_done, %{rows: [[result]]}}} ->
        {:ok, decode_plan(result)}

      {:error, {:explain_error, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}

      {:ok, _} ->
        {:error, :unexpected_commit}
    end
  end

  defp decode_plan(result) when is_binary(result), do: Jason.decode!(result)
  defp decode_plan(result) when is_list(result) or is_map(result), do: result

  defp mutation?(sql) do
    sql
    |> String.trim_leading()
    |> String.upcase()
    |> String.match?(~r/\A(INSERT|UPDATE|DELETE|MERGE)\s/)
  end

  # Run all rules that implement check/3 (EXPLAIN-based rules).
  defp run_plan_rules(nodes, entry, %EctoSpect.Config{rules: rules} = config) do
    rules
    |> Enum.filter(&function_exported?(&1, :check, 3))
    |> Enum.flat_map(& &1.check(nodes, entry, config.thresholds))
  end
end
