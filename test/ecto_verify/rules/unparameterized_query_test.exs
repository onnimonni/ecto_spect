defmodule EctoVerify.Rules.UnparameterizedQueryTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.UnparameterizedQuery

  defp entry(sql, params) do
    %{
      sql: sql,
      params: params,
      source: nil,
      stacktrace: nil,
      repo: MyApp.Repo,
      total_time_us: nil
    }
  end

  defp check(sql, params \\ []), do: UnparameterizedQuery.check([], entry(sql, params), %{})

  describe "check/3" do
    test "detects integer literal in WHERE" do
      violations = check("SELECT * FROM users WHERE id = 42")
      assert length(violations) == 1
    end

    test "detects string literal in WHERE" do
      violations = check("SELECT * FROM users WHERE name = 'Alice'")
      assert length(violations) == 1
    end

    test "does not flag parameterized query" do
      violations = check("SELECT * FROM users WHERE id = $1", [42])
      assert violations == []
    end

    test "does not flag EXPLAIN queries" do
      violations =
        check("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM users WHERE id = 1")

      assert violations == []
    end

    test "does not flag CREATE TABLE" do
      violations = check("CREATE TABLE test (id integer, name text)")
      assert violations == []
    end

    test "does not flag system queries" do
      sql = "SELECT pg_size_pretty(pg_total_relation_size('users'))"
      assert check(sql) == []
    end
  end
end
