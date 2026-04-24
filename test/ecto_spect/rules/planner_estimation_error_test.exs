defmodule EctoSpect.Rules.PlannerEstimationErrorTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.PlannerEstimationError

  defp node(actual_rows, plan_rows, opts \\ []) do
    %{
      node_type: Keyword.get(opts, :node_type, "Seq Scan"),
      actual_rows: actual_rows,
      plan_rows: plan_rows,
      relation_name: Keyword.get(opts, :relation_name, "users"),
      alias: nil,
      index_name: nil,
      index_cond: nil,
      filter: nil,
      join_type: nil,
      sort_key: nil,
      sort_method: nil,
      actual_loops: 1,
      rows_removed_by_filter: 0,
      actual_total_time_ms: 10.0,
      total_cost: 100.0,
      shared_hit_blocks: 0,
      shared_read_blocks: 0,
      shared_dirtied_blocks: 0,
      hash_batches: nil,
      parent_node_type: nil,
      depth: 0
    }
  end

  defp entry, do: %{sql: "SELECT * FROM users", params: [], stacktrace: nil}
  defp thresholds, do: %{estimation_error_ratio: 10, seq_scan_min_rows: 100}

  describe "name/0 and description/0" do
    test "contract" do
      assert PlannerEstimationError.name() == "planner-estimation-error"
      assert is_binary(PlannerEstimationError.description())
    end
  end

  describe "check/3 — underestimation" do
    test "flags when actual >> planned by ratio threshold" do
      # 5000 actual / 10 planned = 500x — well over 10x
      n = node(5000, 10)
      violations = PlannerEstimationError.check([n], entry(), thresholds())
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :warning
      assert String.contains?(v.message, "underestimated")
      assert v.rule == PlannerEstimationError
    end

    test "does not flag when ratio is within threshold" do
      # 500 actual / 100 planned = 5x — under 10x threshold
      n = node(500, 100)
      assert PlannerEstimationError.check([n], entry(), thresholds()) == []
    end
  end

  describe "check/3 — overestimation" do
    test "flags when planned >> actual by ratio threshold" do
      # 10 actual, 5000 planned = 500x over
      n = node(200, 5000)
      violations = PlannerEstimationError.check([n], entry(), thresholds())
      assert length(violations) == 1
      assert String.contains?(hd(violations).message, "overestimated")
    end
  end

  describe "check/3 — below min_rows threshold" do
    test "ignores nodes with actual_rows below seq_scan_min_rows" do
      # actual < min_rows = 100 → skip
      n = node(50, 1)
      assert PlannerEstimationError.check([n], entry(), thresholds()) == []
    end
  end

  describe "check/3 — nil values" do
    test "ignores nodes with nil actual_rows" do
      n = node(nil, 100)
      assert PlannerEstimationError.check([n], entry(), thresholds()) == []
    end

    test "ignores nodes with nil plan_rows" do
      n = node(5000, nil)
      assert PlannerEstimationError.check([n], entry(), thresholds()) == []
    end

    test "ignores nodes with plan_rows = 0" do
      n = node(5000, 0)
      assert PlannerEstimationError.check([n], entry(), thresholds()) == []
    end
  end

  describe "violation shape" do
    test "advice mentions ANALYZE" do
      n = node(10_000, 10)
      [v] = PlannerEstimationError.check([n], entry(), thresholds())
      assert String.contains?(v.advice, "ANALYZE")
    end

    test "details include plan_rows, actual_rows, ratio" do
      n = node(1000, 10)
      [v] = PlannerEstimationError.check([n], entry(), thresholds())
      assert v.details.plan_rows == 10
      assert v.details.actual_rows == 1000
      assert is_float(v.details.ratio)
    end
  end
end
