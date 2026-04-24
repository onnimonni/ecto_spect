defmodule EctoVerify.Rules.OrderWithoutLimitTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.OrderWithoutLimit

  defp entry(sql),
    do: %{sql: sql, params: [], source: nil, stacktrace: nil, repo: nil, total_time_us: nil}

  defp top_node(rows),
    do: [%{node_type: "Sort", actual_rows: rows, plan_rows: rows, sort_key: ["id"], depth: 0}]

  describe "check/3" do
    test "flags ORDER BY without LIMIT when many rows returned" do
      sql = "SELECT id FROM users ORDER BY id"
      nodes = top_node(500)
      assert [v] = OrderWithoutLimit.check(nodes, entry(sql), %{seq_scan_min_rows: 100})
      assert v.severity == :warning
      assert v.rule == OrderWithoutLimit
    end

    test "does not flag when LIMIT present" do
      sql = "SELECT id FROM users ORDER BY id LIMIT $1"
      nodes = top_node(500)
      assert [] = OrderWithoutLimit.check(nodes, entry(sql), %{seq_scan_min_rows: 100})
    end

    test "does not flag when rows below threshold" do
      sql = "SELECT id FROM users ORDER BY id"
      nodes = top_node(10)
      assert [] = OrderWithoutLimit.check(nodes, entry(sql), %{seq_scan_min_rows: 100})
    end

    test "does not flag when no ORDER BY" do
      sql = "SELECT id FROM users"
      nodes = top_node(500)
      assert [] = OrderWithoutLimit.check(nodes, entry(sql), %{seq_scan_min_rows: 100})
    end
  end
end
