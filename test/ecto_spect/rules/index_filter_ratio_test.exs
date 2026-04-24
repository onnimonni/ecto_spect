defmodule EctoSpect.Rules.IndexFilterRatioTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.IndexFilterRatio

  defp entry,
    do: %{
      sql: "SELECT id FROM orders WHERE status = $1",
      params: ["active"],
      source: nil,
      stacktrace: nil,
      repo: nil,
      total_time_us: nil
    }

  defp index_node(returned, removed, index_name \\ "orders_status_idx") do
    %{
      node_type: "Index Scan",
      index_name: index_name,
      relation_name: "orders",
      actual_rows: returned,
      rows_removed_by_filter: removed,
      filter: "(status = 'active')",
      depth: 0
    }
  end

  describe "check/3" do
    test "flags index scan with 10x filter waste" do
      # Index returns 1000, filter keeps 10 → ratio 100x
      assert [v] =
               IndexFilterRatio.check([index_node(10, 1000)], entry(), %{index_filter_ratio: 10})

      assert v.severity == :warning
      assert v.rule == IndexFilterRatio
      assert v.details.ratio == 100.0
    end

    test "does not flag when ratio below threshold" do
      # Index returns 100, filter removes 50 → ratio 0.5x
      assert [] =
               IndexFilterRatio.check([index_node(100, 50)], entry(), %{index_filter_ratio: 10})
    end

    test "does not flag when no rows removed" do
      assert [] = IndexFilterRatio.check([index_node(100, 0)], entry(), %{index_filter_ratio: 10})
    end

    test "does not flag Seq Scan nodes" do
      node = %{
        node_type: "Seq Scan",
        index_name: nil,
        relation_name: "orders",
        actual_rows: 10,
        rows_removed_by_filter: 1000,
        filter: nil,
        depth: 0
      }

      assert [] = IndexFilterRatio.check([node], entry(), %{index_filter_ratio: 10})
    end
  end
end
