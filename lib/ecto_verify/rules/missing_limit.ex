defmodule EctoVerify.Rules.MissingLimit do
  @moduledoc """
  Detects SELECT queries that return many rows without a LIMIT clause.

  Unbounded queries can return millions of rows as the dataset grows, causing
  memory exhaustion and slow response times in production.

  Fires only when EXPLAIN ANALYZE shows `actual_rows >= seq_scan_min_rows`
  on the top-level node (to avoid noise on small result sets).
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "missing-limit"

  @impl true
  def description, do: "Detects SELECT queries that return many rows without LIMIT"

  @impl true
  def check(nodes, entry, thresholds) do
    min_rows = Map.get(thresholds, :seq_scan_min_rows, 100)

    if select?(entry.sql) and not has_limit?(entry.sql) do
      top_node = hd(nodes)
      actual_rows = top_node && top_node.actual_rows

      if actual_rows && actual_rows >= min_rows do
        [
          %EctoVerify.Violation{
            rule: __MODULE__,
            severity: :warning,
            message: "Unbounded SELECT returned #{actual_rows} rows — no LIMIT clause",
            advice: """
            Add a LIMIT clause to prevent unbounded result sets in production.

            With Ecto:
              from(q in query, limit: ^page_size)

            If you need all records, consider pagination with `Repo.stream/2` or
            cursor-based pagination to avoid loading all rows into memory at once.
            """,
            entry: entry,
            details: %{actual_rows: actual_rows}
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp select?(sql) do
    sql |> String.trim_leading() |> String.upcase() |> String.starts_with?("SELECT")
  end

  defp has_limit?(sql) do
    sql |> String.upcase() |> String.contains?(" LIMIT ")
  end
end
