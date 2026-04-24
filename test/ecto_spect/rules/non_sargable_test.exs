defmodule EctoSpect.Rules.NonSargableTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Rules.NonSargable

  defp entry(sql) do
    %{sql: sql, params: [], source: nil, stacktrace: nil, repo: MyApp.Repo, total_time_us: nil}
  end

  defp check(sql), do: NonSargable.check([], entry(sql), %{})

  describe "check/3" do
    test "detects LIKE with leading wildcard" do
      violations = check("SELECT * FROM users WHERE name LIKE '%Alice'")
      assert length(violations) == 1
      assert hd(violations).details.pattern =~ "LIKE"
    end

    test "does not flag LIKE with trailing wildcard" do
      violations = check("SELECT * FROM users WHERE name LIKE 'Alice%'")
      assert violations == []
    end

    test "detects ILIKE with leading wildcard" do
      violations = check("SELECT * FROM users WHERE name ILIKE '%alice'")
      assert length(violations) == 1
    end

    test "detects LOWER() in WHERE" do
      violations = check("SELECT * FROM users WHERE LOWER(email) = $1")
      assert length(violations) == 1
      assert hd(violations).details.pattern =~ "LOWER"
    end

    test "detects UPPER() in WHERE" do
      violations = check("SELECT * FROM users WHERE UPPER(code) = $1")
      assert length(violations) == 1
    end

    test "does not flag safe parameterized query" do
      violations = check("SELECT * FROM users WHERE email = $1")
      assert violations == []
    end

    test "returns empty for non-SELECT" do
      violations = check("INSERT INTO users (name) VALUES ($1)")
      assert violations == []
    end
  end
end
