defmodule EctoVerify.Rules.NonSargable do
  @moduledoc """
  Detects non-SARGable predicates in SQL queries.

  A non-SARGable (Search ARGument able) predicate cannot use an index because
  it wraps the indexed column in a function or uses a leading wildcard pattern.
  These predicates force PostgreSQL to evaluate every row.

  Detected patterns:
  - `LIKE '%value'` (leading wildcard)
  - `ILIKE '%value'` (leading wildcard, case-insensitive)
  - Function calls on columns in WHERE: `LOWER(col)`, `DATE(col)`, `CAST(col AS ...)`
  - `WHERE col::type` (implicit cast on indexed column)
  """

  @behaviour EctoVerify.Rule

  # Patterns that cannot use a standard B-tree index
  @non_sargable_patterns [
    {~r/\bLIKE\s+'%[^']/i, "LIKE with leading wildcard",
     "Use full-text search (`to_tsvector`/`to_tsquery` with GIN index) or `pg_trgm` extension for substring matching."},
    {~r/\bILIKE\s+'%[^']/i, "ILIKE with leading wildcard",
     "Use `pg_trgm` extension with a GIN index: `CREATE INDEX CONCURRENTLY ... USING gin(col gin_trgm_ops);`"},
    {~r/\bLOWER\s*\([^)]+\)\s*=/i, "LOWER() on column in WHERE",
     "Create a functional index: `CREATE INDEX CONCURRENTLY ON table (LOWER(column));`"},
    {~r/\bUPPER\s*\([^)]+\)\s*=/i, "UPPER() on column in WHERE",
     "Create a functional index: `CREATE INDEX CONCURRENTLY ON table (UPPER(column));`"},
    {~r/\bDATE\s*\([^)]+\)\s*=/i, "DATE() on column in WHERE",
     "Use a range condition instead: `WHERE col >= '2024-01-01' AND col < '2024-01-02'`"},
    {~r/\bTO_DATE\s*\([^)]+\)/i, "TO_DATE() on column in WHERE",
     "Store dates as DATE type and compare directly, or create a functional index."},
    {~r/\bEXTRACT\s*\([^)]+FROM\s+[^)]+\)/i, "EXTRACT() on column in WHERE",
     "Use a range condition on the full timestamp column instead."},
    {~r/::[a-z]+\s*(?:=|<|>|IN\b)/i, "Implicit cast (::type) on indexed column",
     "Ensure the comparison value matches the column type without casting, or create a functional index."}
  ]

  @impl true
  def name, do: "non-sargable"

  @impl true
  def description, do: "Detects predicates that cannot use indexes (non-SARGable)"

  @impl true
  def check(_nodes, entry, _thresholds) do
    @non_sargable_patterns
    |> Enum.filter(fn {pattern, _label, _advice} ->
      Regex.match?(pattern, entry.sql)
    end)
    |> Enum.map(fn {_pattern, label, advice} ->
      %EctoVerify.Violation{
        rule: __MODULE__,
        severity: :warning,
        message: "Non-SARGable predicate: #{label}",
        advice: advice,
        entry: entry,
        details: %{pattern: label}
      }
    end)
  end
end
