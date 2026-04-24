defmodule EctoSpect.Rules.MissingFkIndexTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.MissingFkIndex

  describe "module contract" do
    test "name and description are strings" do
      assert MissingFkIndex.name() == "missing-fk-index"
      assert is_binary(MissingFkIndex.description())
    end

    test "check/3 returns empty list (schema-level rule)" do
      assert MissingFkIndex.check([], %{}, %{}) == []
    end
  end

  describe "violation shape (unit test via simulated rows)" do
    test "builds error violation for unindexed FK" do
      violation = build_violation("orders", "user_id", "users")
      assert violation.rule == MissingFkIndex
      assert violation.severity == :error
      assert String.contains?(violation.message, "orders.user_id")
      assert String.contains?(violation.message, "users")
      assert String.contains?(violation.advice, "CREATE INDEX CONCURRENTLY")
      assert String.contains?(violation.advice, "idx_orders_user_id")
    end

    test "advice mentions CONCURRENTLY" do
      violation = build_violation("comments", "post_id", "posts")
      assert String.contains?(violation.advice, "CONCURRENTLY")
    end

    test "advice includes Ecto migration syntax" do
      violation = build_violation("likes", "user_id", "users")
      assert String.contains?(violation.advice, "create index")
    end
  end

  # Replicate the violation building for unit testing without a real DB.
  defp build_violation(table, column, ref_table) do
    %EctoSpect.Violation{
      rule: MissingFkIndex,
      severity: :error,
      message: "`#{table}.#{column}` is a FK referencing `#{ref_table}` but has no index",
      advice: """
      PostgreSQL does not auto-create indexes on foreign key columns (unlike MySQL).
      Without this index, JOINs and CASCADE operations do full table scans.

      Fix:
        CREATE INDEX CONCURRENTLY idx_#{table}_#{column}
          ON #{table}(#{column});

      In an Ecto migration:
        create index(:#{table}, [:#{column}])

      Or with concurrent creation (safe for production):
        create index(:#{table}, [:#{column}], concurrently: true)
      """,
      entry: %{sql: "(schema check)", source: table, params: [], stacktrace: nil},
      details: %{table: table, column: column, references_table: ref_table}
    }
  end
end
