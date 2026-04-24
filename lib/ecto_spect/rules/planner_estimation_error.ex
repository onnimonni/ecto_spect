defmodule EctoSpect.Rules.PlannerEstimationError do
  @moduledoc """
  Detects when PostgreSQL's row count estimate is wildly wrong.

  The query planner uses table statistics to estimate how many rows each plan
  node will produce. When these estimates are far off (actual vs planned), the
  planner may choose an inferior strategy — wrong join order, nested loop instead
  of hash join, or seq scan instead of index scan.

  Common causes:
  - Stale statistics (table modified heavily since last ANALYZE)
  - Unusual data distributions (high correlation, skewed values)
  - Complex predicates the planner cannot estimate well

  Threshold: `estimation_error_ratio` (default: 10×) — flags when actual rows
  are more than 10× the planned estimate, or planned is more than 10× actual.
  Only fires when `actual_rows >= seq_scan_min_rows` to avoid noise on tiny tables.
  """

  @behaviour EctoSpect.Rule

  @impl true
  def name, do: "planner-estimation-error"

  @impl true
  def description,
    do: "Detects large discrepancies between planned and actual row counts (stale statistics)"

  @impl true
  def check(nodes, entry, thresholds) do
    ratio_threshold = Map.get(thresholds, :estimation_error_ratio, 10)
    min_rows = Map.get(thresholds, :seq_scan_min_rows, 100)

    nodes
    |> Enum.filter(fn node ->
      actual = node.actual_rows
      planned = node.plan_rows
      # Only check nodes with meaningful row counts and real data
      actual != nil and planned != nil and planned > 0 and actual >= min_rows and
        (actual / planned > ratio_threshold or planned / max(actual, 1) > ratio_threshold)
    end)
    |> Enum.map(fn node ->
      {ratio, direction} =
        if node.actual_rows > node.plan_rows do
          {Float.round(node.actual_rows / node.plan_rows, 1), "underestimated"}
        else
          {Float.round(node.plan_rows / node.actual_rows, 1), "overestimated"}
        end

      table = node.relation_name || "the relevant table(s)"

      %EctoSpect.Violation{
        rule: __MODULE__,
        severity: :warning,
        message:
          "Planner #{direction} rows #{ratio}× on #{node.node_type} " <>
            "(planned #{node.plan_rows}, actual #{node.actual_rows})",
        advice: """
        PostgreSQL estimated #{node.plan_rows} rows but found #{node.actual_rows} (#{ratio}× off).
        This causes the planner to choose suboptimal join strategies and scan types.

        Fix — update statistics:
          ANALYZE #{table};

        For frequently-updated tables, increase autovacuum sensitivity:
          ALTER TABLE #{table} SET (
            autovacuum_analyze_scale_factor = 0.01,
            autovacuum_analyze_threshold = 100
          );

        Check statistics freshness:
          SELECT tablename, last_analyze, n_live_tup, n_mod_since_analyze
          FROM pg_stat_user_tables
          ORDER BY n_mod_since_analyze DESC;
        """,
        entry: entry,
        details: %{
          plan_rows: node.plan_rows,
          actual_rows: node.actual_rows,
          ratio: ratio,
          direction: direction,
          node_type: node.node_type,
          relation: node.relation_name
        }
      }
    end)
  end
end
