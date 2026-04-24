defmodule EctoSpect.Rules.MissingLimitTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.MissingLimit

  defp plan_node(actual_rows) do
    %{
      node_type: "Seq Scan",
      actual_rows: actual_rows,
      plan_rows: actual_rows,
      relation_name: "users",
      alias: "u0",
      index_name: nil,
      index_cond: nil,
      filter: nil,
      join_type: nil,
      sort_key: nil,
      actual_loops: 1,
      rows_removed_by_filter: 0,
      actual_total_time_ms: 1.0,
      total_cost: 10.0,
      shared_hit_blocks: 5,
      shared_read_blocks: 0,
      shared_dirtied_blocks: 0,
      hash_batches: nil,
      parent_node_type: nil,
      depth: 0
    }
  end

  defp entry(sql), do: %{sql: sql, params: [], cast_params: [], stacktrace: nil}

  describe "name/0 and description/0" do
    test "correct contract" do
      assert MissingLimit.name() == "missing-limit"
      assert is_binary(MissingLimit.description())
    end
  end

  describe "check/3 — fires when SELECT has no LIMIT and rows >= threshold" do
    test "flags unbounded SELECT over threshold" do
      e = entry("SELECT u0.id FROM users AS u0")
      violations = MissingLimit.check([plan_node(500)], e, %{seq_scan_min_rows: 100})
      assert length(violations) == 1
      assert hd(violations).severity == :warning
      assert String.contains?(hd(violations).message, "500")
    end

    test "uses default threshold of 100 when not specified" do
      e = entry("SELECT id FROM users")
      assert MissingLimit.check([plan_node(150)], e, %{}) != []
    end
  end

  describe "check/3 — does not flag when" do
    test "LIMIT is present" do
      e = entry("SELECT id FROM users LIMIT 10")
      assert MissingLimit.check([plan_node(500)], e, %{seq_scan_min_rows: 100}) == []
    end

    test "actual_rows below threshold" do
      e = entry("SELECT id FROM users")
      assert MissingLimit.check([plan_node(50)], e, %{seq_scan_min_rows: 100}) == []
    end

    test "query is not SELECT (INSERT)" do
      e = entry("INSERT INTO users (email) VALUES ($1)")
      assert MissingLimit.check([plan_node(500)], e, %{seq_scan_min_rows: 100}) == []
    end

    test "actual_rows is nil (no EXPLAIN data)" do
      n = plan_node(nil)
      e = entry("SELECT id FROM users")
      assert MissingLimit.check([n], e, %{seq_scan_min_rows: 100}) == []
    end

    test "exactly at threshold boundary does fire" do
      e = entry("SELECT id FROM users")
      assert MissingLimit.check([plan_node(100)], e, %{seq_scan_min_rows: 100}) != []
    end

    test "one below threshold does not fire" do
      e = entry("SELECT id FROM users")
      assert MissingLimit.check([plan_node(99)], e, %{seq_scan_min_rows: 100}) == []
    end
  end

  describe "violation shape" do
    test "includes actual row count in message" do
      e = entry("SELECT id FROM orders")
      [v] = MissingLimit.check([plan_node(999)], e, %{seq_scan_min_rows: 100})
      assert String.contains?(v.message, "999")
      assert v.rule == MissingLimit
      assert String.contains?(v.advice, "LIMIT")
    end
  end
end
