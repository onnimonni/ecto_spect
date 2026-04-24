defmodule EctoSpect.Rules.MigrationChangeColumnTypeTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.MigrationChangeColumnType

  defp check(source) do
    ast = Code.string_to_quoted!(source)
    MigrationChangeColumnType.check_migration(ast, source, "20240101_test.exs")
  end

  describe "name/0 and description/0" do
    test "contract" do
      assert MigrationChangeColumnType.name() == "migration-change-column-type"
      assert is_binary(MigrationChangeColumnType.description())
    end
  end

  describe "check_migration/3" do
    test "flags modify changing column type" do
      source = """
      def change do
        alter table(:users) do
          modify :age, :bigint
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :error
      assert v.rule == MigrationChangeColumnType
      assert String.contains?(v.message, "age")
      assert String.contains?(v.message, "bigint")
    end

    test "flags modify with options (still a type change)" do
      source = """
      def change do
        alter table(:orders) do
          modify :status, :string, null: false
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
      assert String.contains?(hd(violations).message, "status")
    end

    test "flags multiple type changes" do
      source = """
      def change do
        alter table(:users) do
          modify :age, :bigint
          modify :score, :float
        end
      end
      """

      assert length(check(source)) == 2
    end

    test "does not flag add column (not a type change)" do
      source = """
      def change do
        alter table(:users) do
          add :nickname, :string
        end
      end
      """

      assert check(source) == []
    end

    test "does not flag remove column" do
      source = """
      def change do
        alter table(:users) do
          remove :old_col
        end
      end
      """

      assert check(source) == []
    end

    test "advice mentions zero-downtime column add approach" do
      source = """
      def change do
        alter table(:users) do
          modify :score, :float
        end
      end
      """

      [v] = check(source)
      assert String.contains?(v.advice, "new column") or String.contains?(v.advice, "backfill")
    end
  end
end
