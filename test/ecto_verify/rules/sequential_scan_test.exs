defmodule EctoVerify.Rules.SequentialScanTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.SequentialScan

  @entry %{
    sql: ~s[SELECT u0."id" FROM "users" AS u0 WHERE (u0."active" = $1)],
    params: [true],
    source: "users",
    stacktrace: nil,
    repo: MyApp.Repo,
    total_time_us: 5_000
  }

  defp seq_scan_node(actual_rows) do
    %{
      node_type: "Seq Scan",
      relation_name: "users",
      actual_rows: actual_rows,
      plan_rows: actual_rows,
      filter: "(active = true)",
      index_name: nil,
      parent_node_type: nil,
      depth: 0
    }
  end

  defp index_node do
    %{
      node_type: "Index Scan",
      relation_name: "users",
      actual_rows: 1,
      plan_rows: 1,
      index_name: "users_pkey",
      filter: nil,
      parent_node_type: nil,
      depth: 0
    }
  end

  describe "check/3" do
    test "flags seq scan above threshold" do
      nodes = [seq_scan_node(500)]
      violations = SequentialScan.check(nodes, @entry, %{seq_scan_min_rows: 100})

      assert length(violations) == 1
      [v] = violations
      assert v.severity == :error
      assert v.rule == SequentialScan
      assert String.contains?(v.message, "users")
      assert String.contains?(v.message, "500")
    end

    test "does not flag seq scan below threshold" do
      nodes = [seq_scan_node(50)]
      violations = SequentialScan.check(nodes, @entry, %{seq_scan_min_rows: 100})
      assert violations == []
    end

    test "does not flag index scan" do
      nodes = [index_node()]
      violations = SequentialScan.check(nodes, @entry, %{seq_scan_min_rows: 100})
      assert violations == []
    end

    test "uses custom threshold" do
      nodes = [seq_scan_node(30)]
      violations = SequentialScan.check(nodes, @entry, %{seq_scan_min_rows: 10})
      assert length(violations) == 1
    end

    test "includes filter in details" do
      nodes = [seq_scan_node(200)]
      [v] = SequentialScan.check(nodes, @entry, %{seq_scan_min_rows: 100})
      assert v.details.filter == "(active = true)"
    end
  end
end
