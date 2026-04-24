defmodule EctoVerify.Rules.SelectStar do
  @moduledoc """
  Detects `SELECT *` queries.

  Selecting all columns fetches more data than needed, wastes network bandwidth,
  prevents PostgreSQL from using index-only scans, and breaks if columns are
  added or removed. Always select only the columns your code actually uses.

  Note: Ecto generates named columns by default. This rule catches raw
  `Repo.query/2` calls or `fragment/1` expressions that use wildcards.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "select-star"

  @impl true
  def description, do: "Detects SELECT * queries that fetch unnecessary columns"

  @impl true
  def check(_nodes, entry, _thresholds) do
    if select_star?(entry.sql) do
      [
        %EctoVerify.Violation{
          rule: __MODULE__,
          severity: :warning,
          message: "SELECT * fetches all columns — specify only the columns you need",
          advice: """
          Name the columns explicitly to avoid fetching unnecessary data.

          Instead of:
            Repo.query("SELECT * FROM users WHERE id = $1", [id])

          Use:
            from(u in User, where: u.id == ^id, select: {u.id, u.email})

          Benefits: smaller payloads, enables index-only scans, survives schema changes.
          """,
          entry: entry,
          details: %{}
        }
      ]
    else
      []
    end
  end

  # Match `SELECT *` or `SELECT t0.*` (Ecto alias pattern)
  defp select_star?(sql) do
    Regex.match?(~r/\bSELECT\s+(?:\w+\.)?\*/i, sql)
  end
end
