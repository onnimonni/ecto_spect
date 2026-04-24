defmodule EctoVerify.Rules.UnparameterizedQuery do
  @moduledoc """
  Detects SQL queries with literal values interpolated into the query string
  instead of using parameterized placeholders (`$1`, `$2`, ...).

  Unparameterized queries are a SQL injection risk and also prevent PostgreSQL
  from reusing cached query plans across different parameter values.

  This rule ignores schema-level queries (migrations, EXPLAIN itself, etc.)
  and system queries.

  Note: Ecto generates parameterized queries by default. This rule catches
  cases where `Repo.query/2` or `fragment/1` is used with string interpolation.
  """

  @behaviour EctoVerify.Rule

  # Patterns that suggest literal values in WHERE/SET clauses
  # These match things like: WHERE id = 42, WHERE name = 'Alice', WHERE active = true
  @literal_patterns [
    # Integer or float literals in comparison (no $N params present — guarded by should_check?)
    {~r/\bWHERE\b.+=\s*\d+(?:\.\d+)?/i, "integer/float literal in WHERE"},
    # String literals in comparison
    {~r/\bWHERE\b.+=\s*'[^']+'/i, "string literal in WHERE"},
    # IN clause with literal values
    {~r/\bIN\s*\(\s*(?:\d+|'[^']+')\s*(?:,\s*(?:\d+|'[^']+')\s*)*\)/i,
     "literal values in IN clause"},
    # SET with literal values (UPDATE)
    {~r/\bSET\b.+=\s*(?:\d+|'[^']+'|true|false)/i, "literal value in SET clause"}
  ]

  # SQL patterns to ignore (these legitimately contain literals)
  @ignored_prefixes [
    "EXPLAIN",
    "CREATE",
    "DROP",
    "ALTER",
    "GRANT",
    "REVOKE",
    "SET ",
    "SHOW",
    "SELECT pg_",
    "SELECT version",
    "SELECT current_",
    "SELECT COUNT(*) FROM pg_"
  ]

  @impl true
  def name, do: "unparameterized-query"

  @impl true
  def description,
    do: "Detects literal values in SQL strings instead of parameterized placeholders"

  @impl true
  def check(_nodes, entry, _thresholds) do
    if should_check?(entry.sql) do
      @literal_patterns
      |> Enum.filter(fn {pattern, _label} -> Regex.match?(pattern, entry.sql) end)
      |> Enum.map(fn {_pattern, label} ->
        %EctoVerify.Violation{
          rule: __MODULE__,
          severity: :error,
          message: "Possible unparameterized query: #{label} found",
          advice: """
          Use parameterized queries to prevent SQL injection and enable plan caching.

          Instead of:
            Repo.query("SELECT * FROM users WHERE id = \#{id}")

          Use:
            Repo.query("SELECT * FROM users WHERE id = $1", [id])

          With Ecto query syntax, parameterization is automatic:
            from(u in User, where: u.id == ^id)

          With fragments, pin operator ensures parameterization:
            from(u in User, where: fragment("lower(?) = ?", u.name, ^name))
          """,
          entry: entry,
          details: %{pattern: label}
        }
      end)
      |> Enum.take(1)
    else
      []
    end
  end

  defp should_check?(sql) do
    # Skip if query already uses parameters
    has_params = Regex.match?(~r/\$\d+/, sql)
    # Skip schema/system queries
    upper = String.upcase(String.trim_leading(sql))
    is_ignored = Enum.any?(@ignored_prefixes, &String.starts_with?(upper, &1))

    not has_params and not is_ignored
  end
end
