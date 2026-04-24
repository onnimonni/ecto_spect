defmodule EctoSpect.Rules.SortWithoutIndexTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.SortWithoutIndex

  defp entry,
    do: %{
      sql: "SELECT id FROM users ORDER BY inserted_at",
      params: [],
      source: nil,
      stacktrace: nil,
      repo: nil,
      total_time_us: nil
    }

  defp sort_node(rows, key \\ ["inserted_at"]) do
    %{node_type: "Sort", actual_rows: rows, plan_rows: rows, sort_key: key, depth: 0, filter: nil}
  end

  describe "check/3" do
    test "flags Sort node above threshold" do
      assert [v] = SortWithoutIndex.check([sort_node(200)], entry(), %{seq_scan_min_rows: 100})
      assert v.severity == :warning
      assert v.rule == SortWithoutIndex
      assert v.message =~ "200"
      assert v.message =~ "inserted_at"
    end

    test "does not flag Sort below threshold" do
      assert [] = SortWithoutIndex.check([sort_node(50)], entry(), %{seq_scan_min_rows: 100})
    end

    test "does not flag non-Sort nodes" do
      node = %{node_type: "Index Scan", actual_rows: 500, sort_key: nil, depth: 0}
      assert [] = SortWithoutIndex.check([node], entry(), %{seq_scan_min_rows: 100})
    end

    test "uses sort_min_rows threshold when set" do
      assert [] = SortWithoutIndex.check([sort_node(150)], entry(), %{sort_min_rows: 200})
    end
  end
end
