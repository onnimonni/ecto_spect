defmodule EctoSpect.Rules.NotInSubqueryTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.NotInSubquery

  defp entry(sql),
    do: %{sql: sql, params: [], source: nil, stacktrace: nil, repo: nil, total_time_us: nil}

  defp check(sql), do: NotInSubquery.check([], entry(sql), %{})

  describe "check/3" do
    test "flags NOT IN (SELECT ...)" do
      sql = "SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM bans)"
      assert [v] = check(sql)
      assert v.severity == :error
      assert v.rule == NotInSubquery
      assert v.message =~ "NULL"
    end

    test "does not flag NOT IN with literal list" do
      assert [] = check("SELECT * FROM users WHERE status NOT IN ('active', 'pending')")
    end

    test "does not flag IN (SELECT ...)" do
      assert [] = check("SELECT * FROM users WHERE id IN (SELECT user_id FROM admins)")
    end

    test "does not flag NOT EXISTS" do
      sql = "SELECT * FROM users u WHERE NOT EXISTS (SELECT 1 FROM bans b WHERE b.user_id = u.id)"
      assert [] = check(sql)
    end
  end
end
