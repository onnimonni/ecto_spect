defmodule EctoVerify.Rules.MigrationFkNotValidTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.MigrationFkNotValid

  defp check(source) do
    ast = Code.string_to_quoted!(source)
    MigrationFkNotValid.check_migration(ast, source, "20240101_test.exs")
  end

  describe "name/0 and description/0" do
    test "contract" do
      assert MigrationFkNotValid.name() == "migration-fk-not-valid"
      assert is_binary(MigrationFkNotValid.description())
    end
  end

  describe "check_migration/3" do
    test "flags references() without validate: false" do
      source = """
      def change do
        alter table(:orders) do
          add :user_id, references(:users)
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :error
      assert v.rule == MigrationFkNotValid
      assert String.contains?(v.message, "user_id")
    end

    test "flags references() with options but no validate: false" do
      source = """
      def change do
        alter table(:orders) do
          add :user_id, references(:users, type: :bigint, on_delete: :delete_all)
        end
      end
      """

      violations = check(source)
      assert length(violations) == 1
    end

    test "does not flag references() with validate: false" do
      source = """
      def change do
        alter table(:orders) do
          add :user_id, references(:users, validate: false)
        end
      end
      """

      assert check(source) == []
    end

    test "does not flag plain add without references" do
      source = """
      def change do
        alter table(:orders) do
          add :status, :string
        end
      end
      """

      assert check(source) == []
    end

    test "advice mentions NOT VALID and validate separately" do
      source = """
      def change do
        alter table(:orders) do
          add :user_id, references(:users)
        end
      end
      """

      [v] = check(source)
      assert String.contains?(v.advice, "validate: false")
      assert String.contains?(v.advice, "VALIDATE CONSTRAINT")
    end
  end
end
