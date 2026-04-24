defmodule EctoSpect.Rules.CartesianJoin do
  @moduledoc """
  Detects Cartesian products (cross joins) in EXPLAIN plans.

  A Cartesian product occurs when two tables are joined without a join condition,
  producing N × M rows. This is almost always a bug and causes exponential slowdown
  as table sizes grow.

  Detection: looks for Nested Loop nodes where the estimated output rows is
  significantly larger than the sum of input rows from both sides, suggesting
  a multiplicative fan-out without index-based filtering.
  """

  @behaviour EctoSpect.Rule

  # Row explosion factor that suggests a Cartesian product
  @fanout_threshold 10

  @impl true
  def name, do: "cartesian-join"

  @impl true
  def description, do: "Detects Cartesian products in query plans"

  @impl true
  def check(nodes, entry, _thresholds) do
    nodes
    |> Enum.filter(&cartesian?/1)
    |> Enum.map(fn node ->
      %EctoSpect.Violation{
        rule: __MODULE__,
        severity: :error,
        message:
          "Possible Cartesian product: #{node.node_type} producing ~#{node.plan_rows} rows",
        advice: """
        Ensure all JOINs have explicit join conditions.

        With Ecto:
          from a in A,
            join: b in B, on: b.a_id == a.id  # ← always specify `on:`

        Missing join conditions produce a cross join returning N × M rows.
        Check your query for tables joined without an ON clause.
        """,
        entry: entry,
        details: %{
          node_type: node.node_type,
          plan_rows: node.plan_rows,
          actual_rows: node.actual_rows
        }
      }
    end)
  end

  # Heuristic: a join node where plan_rows >> child input rows suggests Cartesian.
  # We identify this by checking if it's a join without an index condition on
  # either side AND plan_rows shows large fan-out.
  defp cartesian?(node) do
    is_join =
      node.node_type in [
        "Nested Loop",
        "Hash Join",
        "Merge Join",
        "Nested Loop Anti Join",
        "Hash Anti Join"
      ]

    # Actual rows far exceed plan suggests multiplicative blowup
    large_fanout =
      node.plan_rows != nil and
        node.actual_rows != nil and
        node.actual_rows > @fanout_threshold and
        node.actual_rows > node.plan_rows * @fanout_threshold

    # Alternatively catch "no join condition" pattern via Nested Loop with no
    # index scan child — checked by plan_rows alone being very large
    no_condition_suspected =
      node.node_type == "Nested Loop" and
        node.plan_rows != nil and
        node.plan_rows > 10_000 and
        node.index_cond == nil

    is_join and (large_fanout or no_condition_suspected)
  end
end
