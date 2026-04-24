defmodule EctoSpect.Rules.NPlusOne do
  @moduledoc """
  Detects N+1 query patterns within a single test.

  An N+1 pattern occurs when the same query (with different parameter values)
  is executed many times in a loop — typically because associations are loaded
  one-by-one instead of being preloaded in bulk.

  This rule does not use EXPLAIN — it analyzes the full list of captured queries
  via `check_group/2`.

  Threshold: `n_plus_one` (default: 5 repeated queries).
  """

  @behaviour EctoSpect.Rule

  @impl true
  def name, do: "n-plus-one"

  @impl true
  def description, do: "Detects N+1 query patterns within a single test"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_group(entries, thresholds) do
    threshold = Map.get(thresholds, :n_plus_one, 5)

    entries
    |> Enum.group_by(&normalize_sql/1)
    |> Enum.filter(fn {_sql, group} -> length(group) >= threshold end)
    |> Enum.map(fn {normalized_sql, group} ->
      count = length(group)
      sample_entry = hd(group)

      %EctoSpect.Violation{
        rule: __MODULE__,
        severity: :error,
        message: "N+1 detected: same query executed #{count} times in one test",
        advice: """
        Batch-load associations instead of querying in a loop.

        With Ecto:
          Repo.preload(records, :association)

        Or use a JOIN in your original query:
          from r in Record, preload: [:association]

        Query template:
          #{String.trim(normalized_sql)}
        """,
        entry: sample_entry,
        details: %{count: count, normalized_sql: normalized_sql}
      }
    end)
  end

  # Strip parameter placeholders ($1, $2, ...) to normalize the query template.
  defp normalize_sql(entry) do
    entry.sql
    |> String.trim()
    |> then(&Regex.replace(~r/\$\d+/, &1, "?"))
  end
end
