defmodule EctoVerify.Rules.UnusedIndexes do
  @moduledoc """
  Detects indexes that were never scanned during the test suite.

  Uses a snapshot-delta approach:
  1. `setup_suite/1` — called before any tests run, records current `idx_scan`
     counts from `pg_stat_user_indexes`.
  2. `check_suite_end/2` — called after all tests complete, compares current
     counts to the snapshot. Indexes with zero delta were never used.

  An unused index in tests likely means one of:
  - No test exercises the query path that uses this index → add tests
  - The index is genuinely unused and should be dropped (saves write overhead)
  - The index exists for a query that always hits a different (better) index

  Primary key indexes are excluded — they are implicitly trusted.
  """

  @behaviour EctoVerify.Rule

  @snapshot_key :ecto_verify_index_scan_snapshot

  @stats_sql """
  SELECT
    s.indexrelname AS index_name,
    s.relname AS table_name,
    COALESCE(s.idx_scan, 0) AS idx_scan,
    ix.indisprimary,
    ix.indisunique
  FROM pg_stat_user_indexes s
  JOIN pg_index ix ON ix.indexrelid = s.indexrelid
  WHERE s.schemaname = 'public'
  ORDER BY s.relname, s.indexrelname
  """

  @impl true
  def name, do: "unused-indexes"

  @impl true
  def description,
    do:
      "Detects indexes never scanned during the test suite (missing test coverage or dead index)"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def setup_suite(conn) do
    case Postgrex.query(conn, @stats_sql, []) do
      {:ok, %{rows: rows}} ->
        snapshot =
          Map.new(rows, fn [index_name, _table, scans, _pk, _unique] ->
            {index_name, scans}
          end)

        Application.put_env(:ecto_verify, @snapshot_key, snapshot)

      {:error, reason} ->
        require Logger
        Logger.debug("[EctoVerify] UnusedIndexes snapshot failed: #{inspect(reason)}")
    end

    :ok
  end

  @impl true
  def check_suite_end(conn, _thresholds) do
    snapshot = Application.get_env(:ecto_verify, @snapshot_key, %{})

    case Postgrex.query(conn, @stats_sql, []) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.reject(fn [_index, _table, _scans, is_pk, _unique] -> is_pk end)
        |> Enum.filter(fn [index_name, _table, current_scans, _pk, _unique] ->
          prior = Map.get(snapshot, index_name, 0)
          current_scans - prior == 0
        end)
        |> Enum.map(&build_violation/1)

      {:error, reason} ->
        require Logger
        Logger.debug("[EctoVerify] UnusedIndexes suite-end check failed: #{inspect(reason)}")
        []
    end
  end

  defp build_violation([index_name, table_name, _scans, _pk, is_unique]) do
    kind = if is_unique, do: "UNIQUE index", else: "Index"

    %EctoVerify.Violation{
      rule: __MODULE__,
      severity: :warning,
      message:
        "#{kind} `#{index_name}` on `#{table_name}` was never scanned during the test suite",
      advice: """
      Two possibilities:

      1. Missing test coverage — maybe you forgot to add tests which use this index?
         Add a test that queries `#{table_name}` using the indexed column(s).
         EctoVerify will confirm the index is used once the query runs through it.

      2. Dead index — the index is genuinely unused and should be dropped:
           DROP INDEX CONCURRENTLY #{index_name};
         This reduces write overhead (every INSERT/UPDATE/DELETE maintains all indexes).

      To check which columns the index covers:
        SELECT indexdef FROM pg_indexes
        WHERE indexname = '#{index_name}';
      """,
      entry: %{sql: "(suite-level check)", source: table_name, params: [], stacktrace: nil},
      details: %{index_name: index_name, table_name: table_name, is_unique: is_unique}
    }
  end
end
