defmodule EctoSpect.Rules.RedundantQueryTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.RedundantQuery

  defp entry(sql, params \\ []) do
    %{sql: sql, params: params, cast_params: [], source: nil, stacktrace: nil}
  end

  describe "name/0 and description/0" do
    test "contract" do
      assert RedundantQuery.name() == "redundant-query"
      assert is_binary(RedundantQuery.description())
    end

    test "check/3 returns empty (group rule)" do
      assert RedundantQuery.check([], %{}, %{}) == []
    end
  end

  describe "check_group/2" do
    test "flags identical SQL+params executed twice" do
      entries = [
        entry("SELECT * FROM users WHERE id = $1", [1]),
        entry("SELECT * FROM users WHERE id = $1", [1])
      ]

      violations = RedundantQuery.check_group(entries, %{})
      assert length(violations) == 1
      v = hd(violations)
      assert v.severity == :warning
      assert v.rule == RedundantQuery
      assert String.contains?(v.message, "2×")
    end

    test "does not flag same SQL with different params (that is N+1 territory)" do
      entries = [
        entry("SELECT * FROM users WHERE id = $1", [1]),
        entry("SELECT * FROM users WHERE id = $1", [2])
      ]

      assert RedundantQuery.check_group(entries, %{}) == []
    end

    test "does not flag unique queries" do
      entries = [
        entry("SELECT * FROM users", []),
        entry("SELECT * FROM posts", [])
      ]

      assert RedundantQuery.check_group(entries, %{}) == []
    end

    test "counts correctly for 3 identical queries" do
      entries = List.duplicate(entry("SELECT 1", []), 3)
      [v] = RedundantQuery.check_group(entries, %{})
      assert String.contains?(v.message, "3×")
      assert v.details.count == 3
    end

    test "handles empty entry list" do
      assert RedundantQuery.check_group([], %{}) == []
    end

    test "advice mentions preload and caching" do
      entries = List.duplicate(entry("SELECT * FROM users WHERE id = $1", [42]), 2)
      [v] = RedundantQuery.check_group(entries, %{})
      assert String.contains?(v.advice, "preload") or String.contains?(v.advice, "Preload")
    end
  end
end
