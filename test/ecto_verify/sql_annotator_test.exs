defmodule EctoVerify.SqlAnnotatorTest do
  use ExUnit.Case, async: true

  alias EctoVerify.SqlAnnotator

  describe "build_comment/1" do
    test "returns empty string when no stacktrace" do
      assert SqlAnnotator.build_comment([]) == ""
      assert SqlAnnotator.build_comment(stacktrace: nil) == ""
      assert SqlAnnotator.build_comment(stacktrace: []) == ""
    end

    test "returns empty string when no opts" do
      assert SqlAnnotator.build_comment([]) == ""
    end

    test "builds comment from stacktrace" do
      stacktrace = [
        {Ecto.Repo.Schema, :insert, 2, [file: ~c"lib/ecto/repo/schema.ex", line: 50]},
        {MyApp.Accounts, :create_user, 1, [file: ~c"lib/my_app/accounts.ex", line: 42]}
      ]

      comment = SqlAnnotator.build_comment(stacktrace: stacktrace)
      assert String.starts_with?(comment, "/*")
      assert String.ends_with?(comment, "*/")
      assert String.contains?(comment, "accounts.ex:42")
      assert String.contains?(comment, "MyApp.Accounts")
    end

    test "skips Ecto internal frames" do
      stacktrace = [
        {Ecto.Repo.Schema, :do_insert, 3, [file: ~c"lib/ecto/repo/schema.ex", line: 100]},
        {Ecto.Adapters.SQL, :query!, 4, [file: ~c"lib/ecto/adapters/sql.ex", line: 300]},
        {MyApp.Orders, :create_order, 2, [file: ~c"lib/my_app/orders.ex", line: 88]}
      ]

      comment = SqlAnnotator.build_comment(stacktrace: stacktrace)
      assert String.contains?(comment, "orders.ex:88")
      refute String.contains?(comment, "schema.ex")
    end
  end
end
