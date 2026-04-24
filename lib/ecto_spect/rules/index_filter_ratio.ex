defmodule EctoSpect.Rules.IndexFilterRatio do
  @moduledoc """
  Detects Index Scans where the index filters out far more rows than it returns.

  An Index Scan reads index entries matching the index condition, then checks
  each row against any additional filter. When `Rows Removed by Filter` >> `Actual Rows`,
  the index is poorly selective — it matches many rows that the filter then discards.

  This typically indicates:
  - The wrong index is being used (a less selective one)
  - A partial index would be much more selective
  - The index covers only part of the WHERE condition (leading columns match but
    trailing columns filter heavily)

  Threshold: filter_ratio (default: 10× — index reads 10x more than it returns).
  """

  @behaviour EctoSpect.Rule

  @impl true
  def name, do: "index-filter-ratio"

  @impl true
  def description,
    do: "Detects Index Scans removing far more rows than returned (poor selectivity)"

  @impl true
  def check(nodes, entry, thresholds) do
    ratio_threshold = Map.get(thresholds, :index_filter_ratio, 10)

    nodes
    |> Enum.filter(fn node ->
      is_index_scan?(node.node_type) and
        has_poor_selectivity?(node, ratio_threshold)
    end)
    |> Enum.map(fn node ->
      removed = node.rows_removed_by_filter || 0
      returned = node.actual_rows || 1
      ratio = Float.round(removed / max(returned, 1), 1)

      %EctoSpect.Violation{
        rule: __MODULE__,
        severity: :warning,
        message:
          "Index `#{node.index_name || "unknown"}` on `#{node.relation_name}` " <>
            "read #{removed + returned} rows, returned #{returned} (#{ratio}× waste)",
        advice: """
        The index matches many rows that the filter then discards.

        Index: #{node.index_name || "unknown"}
        Filter: #{node.filter || "none"}
        Rows read: #{removed + returned}, rows returned: #{returned}

        Options:
        1. Create a more selective partial index covering the filter condition:
             CREATE INDEX CONCURRENTLY idx_<table>_<col>
               ON <table>(<sort_col>)
               WHERE <filter_condition>;

        2. Add the filter column to a composite index (if not already there):
             CREATE INDEX CONCURRENTLY idx_<table>_status_created
               ON <table>(status, created_at);

        3. Check if a different existing index would be more selective for this query.
        """,
        entry: entry,
        details: %{
          index_name: node.index_name,
          relation: node.relation_name,
          rows_returned: returned,
          rows_removed: removed,
          ratio: ratio
        }
      }
    end)
  end

  defp is_index_scan?(type) when type in ["Index Scan", "Index Only Scan", "Bitmap Index Scan"],
    do: true

  defp is_index_scan?(_), do: false

  defp has_poor_selectivity?(node, ratio_threshold) do
    removed = node.rows_removed_by_filter || 0
    returned = node.actual_rows || 0
    # Only flag when actually removing rows (filter exists) with enough volume
    removed > 0 and returned > 0 and removed >= returned * ratio_threshold
  end
end
