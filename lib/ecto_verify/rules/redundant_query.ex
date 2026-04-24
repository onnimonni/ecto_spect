defmodule EctoVerify.Rules.RedundantQuery do
  @moduledoc """
  Detects identical queries (same SQL + same params) executed more than once per test.

  Unlike N+1 detection (which catches the same query template with different params),
  this rule catches exact duplicates — the same SQL with the same parameter values.
  This usually means:
  - A missing `Repo.preload/2` causing the same record to be fetched multiple times
  - A function called twice that issues the same lookup
  - Missing memoization in a resolver or context function

  This rule uses `check_group/2` — it analyzes all queries captured in a single test
  without needing EXPLAIN.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "redundant-query"

  @impl true
  def description,
    do: "Detects identical queries (same SQL + params) executed more than once per test"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_group(entries, _thresholds) do
    entries
    |> Enum.group_by(&query_key/1)
    |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
    |> Enum.map(fn {{sql, params}, group} ->
      count = length(group)
      sample_entry = hd(group)

      %EctoVerify.Violation{
        rule: __MODULE__,
        severity: :warning,
        message: "Redundant query: identical SQL+params executed #{count}× in one test",
        advice: """
        The exact same query (SQL + parameters) ran #{count} times in this test.
        This is different from N+1 — these are exact duplicates, not variations.

        Common causes:
        1. Same record fetched multiple times:
             user = Repo.get!(User, id)
             # Use `user` everywhere — don't call Repo.get!(User, id) again

        2. Missing preload:
             posts = Repo.preload(posts, :author)
             # Instead of loading author inside each post loop

        3. Missing cache in a context function:
             def get_settings(org_id) do
               # Cache this or pass the result down instead of re-calling
               Repo.get!(Settings, org_id)
             end

        Query: #{String.trim(sql)}
        Params: #{inspect(params)}
        """,
        entry: sample_entry,
        details: %{count: count, sql: sql, params: params}
      }
    end)
  end

  defp query_key(entry), do: {String.trim(entry.sql), entry.params}
end
