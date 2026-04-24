defmodule EctoVerify.PlanParserTest do
  use ExUnit.Case, async: true

  alias EctoVerify.PlanParser

  @seq_scan_plan [
    %{
      "Plan" => %{
        "Node Type" => "Seq Scan",
        "Relation Name" => "users",
        "Alias" => "u0",
        "Actual Rows" => 500,
        "Plan Rows" => 450,
        "Actual Loops" => 1,
        "Actual Total Time" => 12.5,
        "Total Cost" => 15.0,
        "Shared Hit Blocks" => 10,
        "Shared Read Blocks" => 5,
        "Filter" => "(active = true)",
        "Plans" => []
      }
    }
  ]

  @nested_plan [
    %{
      "Plan" => %{
        "Node Type" => "Hash Join",
        "Join Type" => "Inner",
        "Actual Rows" => 100,
        "Plan Rows" => 120,
        "Actual Total Time" => 5.0,
        "Total Cost" => 8.0,
        "Plans" => [
          %{
            "Node Type" => "Seq Scan",
            "Relation Name" => "orders",
            "Actual Rows" => 200,
            "Plan Rows" => 180,
            "Actual Total Time" => 3.0,
            "Total Cost" => 4.0
          },
          %{
            "Node Type" => "Index Scan",
            "Relation Name" => "users",
            "Index Name" => "users_pkey",
            "Index Cond" => "(id = $1)",
            "Actual Rows" => 1,
            "Plan Rows" => 1,
            "Actual Total Time" => 0.1,
            "Total Cost" => 0.5
          }
        ]
      }
    }
  ]

  describe "parse/1" do
    test "parses simple seq scan plan" do
      nodes = PlanParser.parse(@seq_scan_plan)

      assert length(nodes) == 1
      [node] = nodes

      assert node.node_type == "Seq Scan"
      assert node.relation_name == "users"
      assert node.actual_rows == 500
      assert node.plan_rows == 450
      assert node.filter == "(active = true)"
      assert node.depth == 0
      assert node.parent_node_type == nil
      assert node.shared_hit_blocks == 10
      assert node.shared_read_blocks == 5
    end

    test "parses nested plan with correct depth and parent tracking" do
      nodes = PlanParser.parse(@nested_plan)

      assert length(nodes) == 3

      [join, seq, index] = nodes

      assert join.node_type == "Hash Join"
      assert join.depth == 0
      assert join.parent_node_type == nil

      assert seq.node_type == "Seq Scan"
      assert seq.relation_name == "orders"
      assert seq.depth == 1
      assert seq.parent_node_type == "Hash Join"

      assert index.node_type == "Index Scan"
      assert index.relation_name == "users"
      assert index.depth == 1
      assert index.parent_node_type == "Hash Join"
      assert index.index_name == "users_pkey"
    end

    test "returns empty list for malformed input" do
      assert PlanParser.parse([]) == []
      assert PlanParser.parse(nil) == []
      assert PlanParser.parse([%{"no_plan" => true}]) == []
    end
  end
end
