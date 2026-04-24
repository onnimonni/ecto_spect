defmodule EctoVerify.Rules.SelectStarTest do
  use ExUnit.Case, async: true

  alias EctoVerify.Rules.SelectStar

  defp entry(sql),
    do: %{sql: sql, params: [], source: nil, stacktrace: nil, repo: nil, total_time_us: nil}

  defp check(sql), do: SelectStar.check([], entry(sql), %{})

  describe "check/3" do
    test "flags SELECT *" do
      assert [v] = check("SELECT * FROM users WHERE id = $1")
      assert v.severity == :warning
      assert v.rule == SelectStar
    end

    test "flags SELECT t0.*" do
      assert [_] = check(~S[SELECT t0.* FROM "users" AS t0])
    end

    test "does not flag named columns" do
      assert [] = check(~S[SELECT u0."id", u0."email" FROM "users" AS u0])
    end

    test "does not flag INSERT" do
      assert [] = check("INSERT INTO users (name) VALUES ($1)")
    end
  end
end
