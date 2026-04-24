defmodule EctoSpect.Rules.IndexCount do
  @compile {:no_warn_undefined, Postgrex}

  @moduledoc """
  Warns when a table has too many indexes, which slows down writes.

  Every INSERT, UPDATE, or DELETE must update all indexes on the table.
  A table with 15 indexes requires 15 index updates per row modification,
  which adds significant overhead in write-heavy workloads.

  This rule does not use EXPLAIN — it queries `pg_indexes` directly.
  It is run once per test module via `check_schema/2`.

  Threshold: `max_indexes` (default: 10).
  """

  @behaviour EctoSpect.Rule

  @query """
  SELECT tablename, COUNT(*) AS index_count
  FROM pg_indexes
  WHERE schemaname = 'public'
  GROUP BY tablename
  HAVING COUNT(*) > $1
  ORDER BY index_count DESC
  """

  @impl true
  def name, do: "index-count"

  @impl true
  def description, do: "Warns when tables have too many indexes (slows writes)"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_schema(conn, thresholds) do
    max = Map.get(thresholds, :max_indexes, 10)

    case Postgrex.query(conn, @query, [max]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [table, count] ->
          %EctoSpect.Violation{
            rule: __MODULE__,
            severity: :warning,
            message: "Table `#{table}` has #{count} indexes (threshold: #{max})",
            advice: """
            Too many indexes slow INSERT, UPDATE, and DELETE on `#{table}`.
            Every write must update all #{count} indexes.

            Review and consolidate:
            1. Find unused indexes:
               SELECT * FROM pg_stat_user_indexes
               WHERE idx_scan = 0 AND relname = '#{table}';

            2. Replace multiple single-column indexes with composite indexes
               where queries filter on multiple columns together.

            3. Drop unused indexes:
               DROP INDEX CONCURRENTLY <index_name>;
            """,
            entry: %{sql: "(schema check)", source: table, params: [], stacktrace: nil},
            details: %{table: table, index_count: count, threshold: max}
          }
        end)

      {:error, reason} ->
        require Logger
        Logger.debug("[EctoSpect] IndexCount schema check failed: #{inspect(reason)}")
        []
    end
  end
end
