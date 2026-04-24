defmodule EctoVerify.Rules.SequentialScan do
  @moduledoc """
  Detects sequential (full table) scans on non-trivial tables.

  A sequential scan on a large table indicates a missing index on the filtered
  columns. PostgreSQL uses seq scans when no suitable index exists or when the
  table is too small for an index to help.

  Threshold: `seq_scan_min_rows` (default: 100 rows).
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "sequential-scan"

  @impl true
  def description, do: "Detects sequential scans on non-trivial tables"

  @impl true
  def check(nodes, entry, thresholds) do
    min_rows = Map.get(thresholds, :seq_scan_min_rows, 100)

    nodes
    |> Enum.filter(fn node ->
      node.node_type == "Seq Scan" and
        (node.actual_rows || 0) >= min_rows
    end)
    |> Enum.map(fn node ->
      table = node.relation_name || "unknown"
      rows = node.actual_rows

      filter_hint =
        if node.filter,
          do: "\n    Filter applied: #{node.filter}",
          else: ""

      %EctoVerify.Violation{
        rule: __MODULE__,
        severity: :error,
        message: "Sequential scan on `#{table}` touching #{format_rows(rows)} rows",
        advice: """
        Add an index on the filtered column(s).#{filter_hint}

        Example:
          CREATE INDEX CONCURRENTLY idx_#{table}_<column> ON #{table}(<column>);

        For boolean or low-cardinality columns, use a partial index:
          CREATE INDEX CONCURRENTLY idx_#{table}_active ON #{table}(id) WHERE active = true;
        """,
        entry: entry,
        details: %{
          relation: table,
          actual_rows: rows,
          filter: node.filter
        }
      }
    end)
  end

  defp format_rows(nil), do: "unknown"

  defp format_rows(n) when n >= 1_000_000,
    do: "#{div(n, 1_000_000)}M"

  defp format_rows(n) when n >= 1_000,
    do: "#{div(n, 1_000)}K"

  defp format_rows(n), do: Integer.to_string(n)
end
