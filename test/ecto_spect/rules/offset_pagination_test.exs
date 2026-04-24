defmodule EctoSpect.Rules.OffsetPaginationTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.OffsetPagination

  defp entry(sql),
    do: %{sql: sql, params: [], source: nil, stacktrace: nil, repo: nil, total_time_us: nil}

  defp check(sql), do: OffsetPagination.check([], entry(sql), %{})

  describe "check/3" do
    test "flags SELECT with OFFSET" do
      sql = "SELECT * FROM users ORDER BY id LIMIT $1 OFFSET $2"
      assert [v] = check(sql)
      assert v.severity == :warning
      assert v.rule == OffsetPagination
    end

    test "does not flag SELECT without OFFSET" do
      assert [] = check("SELECT * FROM users ORDER BY id LIMIT $1")
    end

    test "does not flag UPDATE with OFFSET" do
      assert [] = check("UPDATE users SET active = $1 OFFSET $2")
    end
  end
end
