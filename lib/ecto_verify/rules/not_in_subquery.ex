defmodule EctoVerify.Rules.NotInSubquery do
  @moduledoc """
  Detects NOT IN with a subquery.

  `NOT IN (SELECT ...)` has a correctness trap: if the subquery returns any NULL
  value, the entire NOT IN expression evaluates to NULL (not TRUE), silently
  returning zero rows. This is a common source of bugs.

  Additionally, NOT IN forces PostgreSQL to scan the full subquery result for
  every outer row. `NOT EXISTS` or a LEFT JOIN anti-pattern is both safer and
  typically faster.

  Example of the NULL bug:
    SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM bans);
    -- If any bans.user_id IS NULL → returns 0 rows, not the expected result!
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "not-in-subquery"

  @impl true
  def description, do: "Detects NOT IN (subquery) — NULL trap and performance risk"

  @impl true
  def check(_nodes, entry, _thresholds) do
    if Regex.match?(~r/\bNOT\s+IN\s*\(\s*SELECT\b/i, entry.sql) do
      [
        %EctoVerify.Violation{
          rule: __MODULE__,
          severity: :error,
          message: "NOT IN (subquery) — NULL values in subquery silently break the result",
          advice: """
          Replace NOT IN with NOT EXISTS or a LEFT JOIN anti-pattern.

          NOT EXISTS (NULL-safe, usually faster):
            SELECT * FROM users u
            WHERE NOT EXISTS (
              SELECT 1 FROM bans b WHERE b.user_id = u.id
            );

          With Ecto:
            from u in User,
              where: u.id not in subquery(from b in Ban, select: b.user_id)
            # ↑ still uses NOT IN — use a join instead:

            from u in User,
              left_join: b in Ban, on: b.user_id == u.id,
              where: is_nil(b.id)

          The NULL trap: if subquery returns any NULL, NOT IN returns no rows at all.
          """,
          entry: entry,
          details: %{}
        }
      ]
    else
      []
    end
  end
end
