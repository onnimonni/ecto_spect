defmodule EctoVerify.Rules.MigrationColumnNotNullTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.MigrationColumnNotNull

  defp check(source) do
    ast = Code.string_to_quoted!(source)
    MigrationColumnNotNull.check_migration(ast, source, "20240101_test.exs")
  end

  describe "name/0 and description/0" do
    test "contract" do
      assert MigrationColumnNotNull.name() == "migration-column-not-null"
      assert is_binary(MigrationColumnNotNull.description())
    end
  end

  describe "check_migration/3" do
    test "flags add column with null: false and no default" do
      source = """
      def change do
        alter table(:users) do
          add :status, :string, null: false
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :error
      assert v.rule == MigrationColumnNotNull
      assert String.contains?(v.message, "status")
      assert String.contains?(v.message, "null: false")
    end

    test "does not flag add column with null: false AND default" do
      source = """
      def change do
        alter table(:users) do
          add :status, :string, null: false, default: "active"
        end
      end
      """

      assert check(source) == []
    end

    test "does not flag nullable column (null: true or no null option)" do
      source = """
      def change do
        alter table(:users) do
          add :bio, :text
        end
      end
      """

      assert check(source) == []
    end

    test "does not flag column with null: true explicitly" do
      source = """
      def change do
        alter table(:users) do
          add :bio, :text, null: true
        end
      end
      """

      assert check(source) == []
    end

    test "flags inside create table too" do
      source = """
      def change do
        create table(:posts) do
          add :title, :string, null: false
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
    end

    test "advice mentions backfill approach" do
      source = "def change, do: (alter table(:t), do: add(:col, :string, null: false))"
      violations = check(source)

      if violations != [] do
        [v] = violations
        assert String.contains?(v.advice, "backfill") or String.contains?(v.advice, "Backfill")
      end
    end
  end
end
