defmodule EctoVerify.Rules.NPlusOneTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.NPlusOne

  @user_sql ~S[SELECT u0."id" FROM "users" AS u0 WHERE u0."id" = $1]
  @order_sql ~S[SELECT o0."id" FROM "orders" AS o0 WHERE o0."user_id" = $1]

  defp entry(sql, params \\ []) do
    %{
      sql: sql,
      params: params,
      source: nil,
      stacktrace: nil,
      repo: MyApp.Repo,
      total_time_us: 100
    }
  end

  defp user_query(id), do: entry(@user_sql, [id])

  describe "check/3" do
    test "returns empty list (N+1 uses check_group)" do
      assert NPlusOne.check([], entry("SELECT 1"), %{}) == []
    end
  end

  describe "check_group/2" do
    test "detects N+1 when same query repeats above threshold" do
      entries = Enum.map(1..6, &user_query/1)
      violations = NPlusOne.check_group(entries, %{n_plus_one: 5})

      assert length(violations) == 1
      [v] = violations
      assert v.severity == :error
      assert v.rule == NPlusOne
      assert String.contains?(v.message, "6 times")
      assert v.details.count == 6
    end

    test "does not fire below threshold" do
      entries = Enum.map(1..4, &user_query/1)
      violations = NPlusOne.check_group(entries, %{n_plus_one: 5})
      assert violations == []
    end

    test "treats different queries independently" do
      user_queries = Enum.map(1..6, &user_query/1)

      order_queries =
        Enum.map(1..3, fn id ->
          entry(@order_sql, [id])
        end)

      violations = NPlusOne.check_group(user_queries ++ order_queries, %{n_plus_one: 5})
      # Only user queries cross the threshold
      assert length(violations) == 1
      assert violations |> hd() |> Map.get(:details) |> Map.get(:count) == 6
    end

    test "normalizes params when grouping" do
      entries = Enum.map(1..5, fn id -> entry(@user_sql, [id]) end)
      violations = NPlusOne.check_group(entries, %{n_plus_one: 5})
      assert length(violations) == 1
    end

    test "returns empty list for empty entries" do
      assert NPlusOne.check_group([], %{n_plus_one: 5}) == []
    end
  end
end
