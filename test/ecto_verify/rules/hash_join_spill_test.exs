defmodule EctoVerify.Rules.HashJoinSpillTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.HashJoinSpill

  defp entry,
    do: %{
      sql: "SELECT * FROM a JOIN b ON b.a_id = a.id",
      params: [],
      source: nil,
      stacktrace: nil,
      repo: nil,
      total_time_us: nil
    }

  defp hash_node(batches) do
    %{node_type: "Hash", hash_batches: batches, actual_rows: 1000, depth: 1}
  end

  describe "check/3" do
    test "flags Hash node with Batches > 1" do
      assert [v] = HashJoinSpill.check([hash_node(4)], entry(), %{})
      assert v.severity == :error
      assert v.rule == HashJoinSpill
      assert v.message =~ "4 batches"
    end

    test "does not flag Hash node with Batches = 1" do
      assert [] = HashJoinSpill.check([hash_node(1)], entry(), %{})
    end

    test "does not flag non-Hash nodes" do
      node = %{node_type: "Seq Scan", hash_batches: nil, actual_rows: 1000, depth: 0}
      assert [] = HashJoinSpill.check([node], entry(), %{})
    end
  end
end
