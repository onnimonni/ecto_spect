defmodule EctoSpect.Rules.SortWithoutIndex do
  @moduledoc """
  Detects explicit Sort nodes in EXPLAIN plans with non-trivial row counts.

  When PostgreSQL cannot satisfy an ORDER BY using an index scan (which returns
  rows in order for free), it adds a Sort node that reads all rows, sorts them
  in memory (or spills to disk if they exceed `work_mem`), then returns them.

  A Sort node is often the most expensive operation in a query and a sign that
  an index on the ORDER BY column(s) would help.

  Threshold: `sort_min_rows` (default: same as `seq_scan_min_rows`, 100 rows).
  """

  @behaviour EctoSpect.Rule

  @impl true
  def name, do: "sort-without-index"

  @impl true
  def description, do: "Detects Sort nodes in EXPLAIN plans — missing ORDER BY index"

  @impl true
  def check(nodes, entry, thresholds) do
    min_rows = Map.get(thresholds, :sort_min_rows, Map.get(thresholds, :seq_scan_min_rows, 100))

    nodes
    |> Enum.filter(fn node ->
      node.node_type == "Sort" and
        (node.actual_rows || 0) >= min_rows
    end)
    |> Enum.map(fn node ->
      sort_cols =
        case node.sort_key do
          [_ | _] = keys -> Enum.join(keys, ", ")
          _ -> "unknown column(s)"
        end

      %EctoSpect.Violation{
        rule: __MODULE__,
        severity: :warning,
        message: "In-memory Sort of #{node.actual_rows} rows on #{sort_cols}",
        advice: """
        Add an index on the ORDER BY column(s) to avoid the sort.

        Sort key: #{sort_cols}

        Example:
          CREATE INDEX CONCURRENTLY idx_<table>_<col> ON <table>(<col>);

        With a matching index, PostgreSQL uses an Index Scan that returns rows
        in sorted order — no sort step needed.

        If combined with a WHERE filter, a composite index covering both the
        filter column and sort column is most efficient:
          CREATE INDEX CONCURRENTLY idx_<table>_active_inserted
            ON <table>(active, inserted_at DESC)
            WHERE active = true;
        """,
        entry: entry,
        details: %{actual_rows: node.actual_rows, sort_key: node.sort_key}
      }
    end)
  end
end
