defmodule EctoVerify.Rules.SortSpillToDiskTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.SortSpillToDisk

  defp plan_node(opts) do
    %{
      node_type: Keyword.get(opts, :node_type, "Sort"),
      sort_method: Keyword.get(opts, :sort_method, nil),
      sort_key: Keyword.get(opts, :sort_key, ["col"]),
      actual_rows: Keyword.get(opts, :actual_rows, 1000),
      plan_rows: 1000,
      relation_name: nil,
      alias: nil,
      index_name: nil,
      index_cond: nil,
      filter: nil,
      join_type: nil,
      actual_loops: 1,
      rows_removed_by_filter: 0,
      actual_total_time_ms: 100.0,
      total_cost: 500.0,
      shared_hit_blocks: 0,
      shared_read_blocks: 0,
      shared_dirtied_blocks: 0,
      hash_batches: nil,
      parent_node_type: nil,
      depth: 0
    }
  end

  defp entry, do: %{sql: "SELECT * FROM t ORDER BY col", params: [], stacktrace: nil}

  describe "name/0 and description/0" do
    test "contract" do
      assert SortSpillToDisk.name() == "sort-spill-to-disk"
      assert is_binary(SortSpillToDisk.description())
    end
  end

  describe "check/3" do
    test "flags Sort node with external merge sort method" do
      n = plan_node(sort_method: "external merge Disk: 12800kB")
      violations = SortSpillToDisk.check([n], entry(), %{})
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :error
      assert String.contains?(v.message, "external merge")
      assert v.rule == SortSpillToDisk
    end

    test "does not flag Sort with in-memory quicksort" do
      n = plan_node(sort_method: "quicksort Memory: 25kB")
      assert SortSpillToDisk.check([n], entry(), %{}) == []
    end

    test "does not flag Sort with nil sort_method" do
      n = plan_node(sort_method: nil)
      assert SortSpillToDisk.check([n], entry(), %{}) == []
    end

    test "does not flag non-Sort nodes" do
      n = plan_node(node_type: "Hash", sort_method: "external merge Disk: 1kB")
      assert SortSpillToDisk.check([n], entry(), %{}) == []
    end

    test "includes sort_key in message" do
      n = plan_node(sort_method: "external merge Disk: 5kB", sort_key: ["created_at", "id"])
      [v] = SortSpillToDisk.check([n], entry(), %{})
      assert String.contains?(v.message, "created_at")
    end

    test "advice mentions work_mem and index" do
      n = plan_node(sort_method: "external merge Disk: 5kB")
      [v] = SortSpillToDisk.check([n], entry(), %{})
      assert String.contains?(v.advice, "work_mem")
      assert String.contains?(v.advice, "INDEX")
    end
  end
end
