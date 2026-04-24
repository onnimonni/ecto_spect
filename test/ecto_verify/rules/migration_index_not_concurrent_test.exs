defmodule EctoVerify.Rules.MigrationIndexNotConcurrentTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.MigrationIndexNotConcurrent

  defp parse(source) do
    Code.string_to_quoted!(source)
  end

  defp check(source) do
    ast = parse(source)
    MigrationIndexNotConcurrent.check_migration(ast, source, "20240101_test.exs")
  end

  describe "name/0 and description/0" do
    test "contract" do
      assert MigrationIndexNotConcurrent.name() == "migration-index-not-concurrent"
      assert is_binary(MigrationIndexNotConcurrent.description())
    end

    test "check/3 returns empty (migration rule)" do
      assert MigrationIndexNotConcurrent.check([], %{}, %{}) == []
    end
  end

  describe "check_migration/3" do
    test "flags create index without concurrently" do
      source = """
      defmodule MyApp.Repo.Migrations.AddIndex do
        use Ecto.Migration
        def change do
          create index(:users, [:email])
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :error
      assert v.rule == MigrationIndexNotConcurrent
      assert String.contains?(v.message, "CONCURRENTLY")
    end

    test "does not flag create index with concurrently: true" do
      source = """
      defmodule MyApp.Repo.Migrations.AddIndex do
        use Ecto.Migration
        @disable_ddl_transaction true
        @disable_migration_lock true
        def change do
          create index(:users, [:email], concurrently: true)
        end
      end
      """

      assert check(source) == []
    end

    test "flags multiple non-concurrent indexes" do
      source = """
      def change do
        create index(:users, [:email])
        create index(:posts, [:user_id])
      end
      """

      violations = check(source)
      assert length(violations) == 2
    end

    test "does not flag create table (not an index)" do
      source = """
      def change do
        create table(:users) do
          add :email, :string
        end
      end
      """

      assert check(source) == []
    end

    test "advice mentions @disable_ddl_transaction" do
      source = "def change, do: create index(:t, [:c])"
      [v] = check(source)
      assert String.contains?(v.advice, "@disable_ddl_transaction")
    end
  end
end
