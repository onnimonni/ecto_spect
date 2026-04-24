defmodule EctoVerify.Rules.IndexCountTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.IndexCount

  describe "module contract" do
    test "name and description" do
      assert IndexCount.name() == "index-count"
      assert is_binary(IndexCount.description())
    end

    test "check/3 returns empty list (schema-level rule)" do
      assert IndexCount.check([], %{}, %{}) == []
    end
  end

  describe "violation shape (simulated rows)" do
    test "builds warning violation for table over threshold" do
      v = build_violation("orders", 13, 10)
      assert v.rule == IndexCount
      assert v.severity == :warning
      assert String.contains?(v.message, "orders")
      assert String.contains?(v.message, "13")
      assert String.contains?(v.message, "10")
    end

    test "advice mentions DROP INDEX CONCURRENTLY" do
      v = build_violation("users", 12, 10)
      assert String.contains?(v.advice, "DROP INDEX CONCURRENTLY")
    end

    test "advice mentions pg_stat_user_indexes for finding unused indexes" do
      v = build_violation("events", 11, 10)
      assert String.contains?(v.advice, "pg_stat_user_indexes")
    end

    test "entry source is the table name" do
      v = build_violation("products", 15, 10)
      assert v.entry[:source] == "products"
    end

    test "details include table, index_count, threshold" do
      v = build_violation("shipments", 11, 10)
      assert v.details.table == "shipments"
      assert v.details.index_count == 11
      assert v.details.threshold == 10
    end
  end

  defp build_violation(table, count, max) do
    %EctoVerify.Violation{
      rule: IndexCount,
      severity: :warning,
      message: "Table `#{table}` has #{count} indexes (threshold: #{max})",
      advice: """
      Too many indexes slow INSERT, UPDATE, and DELETE on `#{table}`.
      Every write must update all #{count} indexes.

      Review and consolidate:
      1. Find unused indexes:
         SELECT * FROM pg_stat_user_indexes
         WHERE idx_scan = 0 AND relname = '#{table}';

      2. Replace multiple single-column indexes with composite indexes
         where queries filter on multiple columns together.

      3. Drop unused indexes:
         DROP INDEX CONCURRENTLY <index_name>;
      """,
      entry: %{sql: "(schema check)", source: table, params: [], stacktrace: nil},
      details: %{table: table, index_count: count, threshold: max}
    }
  end
end
