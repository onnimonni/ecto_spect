defmodule EctoVerify.Rules.OrderWithoutLimit do
  @moduledoc """
  Detects ORDER BY without a LIMIT clause when actual rows returned are non-trivial.

  Sorting a large result set in PostgreSQL requires reading all matching rows,
  sorting them in memory (or spilling to disk), then returning everything.
  Without a LIMIT, the full sorted dataset is transferred to the application.
  As the table grows this becomes increasingly expensive.

  Only fires when EXPLAIN shows actual_rows >= seq_scan_min_rows threshold
  to avoid noise on small tables.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "order-without-limit"

  @impl true
  def description, do: "Detects ORDER BY without LIMIT on non-trivial result sets"

  @impl true
  def check(nodes, entry, thresholds) do
    min_rows = Map.get(thresholds, :seq_scan_min_rows, 100)

    if has_order_by?(entry.sql) and not has_limit?(entry.sql) do
      top = List.first(nodes)
      actual_rows = top && top.actual_rows

      if actual_rows && actual_rows >= min_rows do
        [
          %EctoVerify.Violation{
            rule: __MODULE__,
            severity: :warning,
            message: "ORDER BY without LIMIT returned #{actual_rows} sorted rows",
            advice: """
            Add a LIMIT to cap the result set, or use cursor-based pagination.

            With Ecto:
              from(q in query, order_by: [asc: q.inserted_at], limit: ^page_size)

            For "get all sorted" use cases, consider whether sorting in the
            application layer (after filtering) is cheaper than a DB sort.

            For large paginated lists, cursor-based pagination avoids full sorts:
              from(q in query, where: q.id > ^last_id, order_by: q.id, limit: ^page_size)
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

  defp has_order_by?(sql), do: Regex.match?(~r/\bORDER\s+BY\b/i, sql)
  defp has_limit?(sql), do: Regex.match?(~r/\bLIMIT\b/i, sql)
end
