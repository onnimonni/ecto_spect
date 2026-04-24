defmodule EctoSpect.Rules.CartesianJoinTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.CartesianJoin

  defp plan_node(opts) do
    %{
      node_type: Keyword.get(opts, :node_type, "Nested Loop"),
      plan_rows: Keyword.get(opts, :plan_rows, nil),
      actual_rows: Keyword.get(opts, :actual_rows, nil),
      index_cond: Keyword.get(opts, :index_cond, nil),
      relation_name: nil,
      alias: nil,
      index_name: nil,
      filter: nil,
      join_type: nil,
      sort_key: nil,
      actual_loops: nil,
      rows_removed_by_filter: nil,
      actual_total_time_ms: nil,
      total_cost: nil,
      shared_hit_blocks: nil,
      shared_read_blocks: nil,
      shared_dirtied_blocks: nil,
      hash_batches: nil,
      parent_node_type: nil,
      depth: 0
    }
  end

  defp entry, do: %{sql: "SELECT * FROM a, b", params: [], stacktrace: nil}

  describe "name/0 and description/0" do
    test "correct contract" do
      assert CartesianJoin.name() == "cartesian-join"
      assert is_binary(CartesianJoin.description())
    end
  end

  describe "check/3 — large fanout heuristic" do
    test "flags nested loop where actual_rows >> plan_rows * 10" do
      n = plan_node(node_type: "Nested Loop", plan_rows: 10, actual_rows: 5_000)
      violations = CartesianJoin.check([n], entry(), %{})
      assert length(violations) == 1
      assert hd(violations).severity == :error
      assert String.contains?(hd(violations).message, "Cartesian")
    end

    test "does not flag when actual_rows within threshold" do
      n = plan_node(node_type: "Nested Loop", plan_rows: 100, actual_rows: 150)
      assert CartesianJoin.check([n], entry(), %{}) == []
    end
  end

  describe "check/3 — no_condition_suspected heuristic" do
    test "flags Nested Loop with plan_rows > 10_000 and no index_cond" do
      n =
        plan_node(
          node_type: "Nested Loop",
          plan_rows: 50_000,
          actual_rows: 50_000,
          index_cond: nil
        )

      violations = CartesianJoin.check([n], entry(), %{})
      assert length(violations) == 1
    end

    test "does not flag Nested Loop with index_cond present" do
      n =
        plan_node(
          node_type: "Nested Loop",
          plan_rows: 50_000,
          actual_rows: 50_000,
          index_cond: "(a.id = b.a_id)"
        )

      assert CartesianJoin.check([n], entry(), %{}) == []
    end

    test "does not flag Nested Loop with plan_rows <= 10_000" do
      n =
        plan_node(node_type: "Nested Loop", plan_rows: 5_000, actual_rows: 5_000, index_cond: nil)

      assert CartesianJoin.check([n], entry(), %{}) == []
    end
  end

  describe "check/3 — non-join node types" do
    test "does not flag Seq Scan even with large rows" do
      n = plan_node(node_type: "Seq Scan", plan_rows: 1_000_000, actual_rows: 1_000_000)
      assert CartesianJoin.check([n], entry(), %{}) == []
    end
  end

  describe "check/3 — violation shape" do
    test "violation has rule, severity, message, advice" do
      n = plan_node(node_type: "Nested Loop", plan_rows: 50_000, actual_rows: 50_000)
      [v] = CartesianJoin.check([n], entry(), %{})
      assert v.rule == CartesianJoin
      assert v.severity == :error
      assert is_binary(v.message)
      assert String.contains?(v.advice, "JOIN")
    end
  end
end
