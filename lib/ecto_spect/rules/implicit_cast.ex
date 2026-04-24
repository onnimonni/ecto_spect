defmodule EctoSpect.Rules.ImplicitCast do
  @moduledoc """
  Detects implicit type casts in EXPLAIN Filter and Index Cond expressions
  that prevent index usage.

  When a column is cast to a different type in a WHERE clause, PostgreSQL cannot
  use a regular B-tree index on that column. The cast must be evaluated for every
  row, forcing a sequential scan.

  This is distinct from `NonSargable` which catches cast patterns in the raw SQL
  text. This rule reads the EXPLAIN plan output, where PostgreSQL shows the actual
  filter expression it evaluated — including casts injected by the planner itself
  (e.g., implicit casts from type mismatch between column and comparison value).

  Example: comparing a TEXT column against an INTEGER literal causes PostgreSQL
  to implicitly cast the column, bypassing its index.
  """

  @behaviour EctoSpect.Rule

  # Match CAST(...) or ::type patterns in filter/index_cond strings from EXPLAIN
  @cast_patterns [
    {~r/\bCAST\s*\(/i, "CAST() expression"},
    {~r/\b\w+\s*::\s*(?:text|varchar|integer|bigint|numeric|boolean|date|timestamptz?|uuid)\b/i,
     "implicit cast (::type)"}
  ]

  @impl true
  def name, do: "implicit-cast"

  @impl true
  def description,
    do: "Detects type casts in EXPLAIN filter expressions that prevent index scans"

  @impl true
  def check(nodes, entry, _thresholds) do
    nodes
    |> Enum.flat_map(fn node ->
      fields = [{"Filter", node.filter}, {"Index Cond", node.index_cond}]

      for {field_name, text} <- fields,
          is_binary(text),
          {pattern, label} <- @cast_patterns,
          Regex.match?(pattern, text) do
        %EctoSpect.Violation{
          rule: __MODULE__,
          severity: :warning,
          message:
            "#{label} in #{field_name} may bypass index on `#{node.relation_name || node.node_type}`",
          advice: """
          A type cast in a filter expression prevents PostgreSQL from using the index
          on that column. The cast is evaluated per-row, forcing a sequential scan.

          Expression: #{text}

          Fix options:

          1. Match parameter type to column type — ensure Ecto schema field type
             matches the database column type:
               field :status, :string  # not :integer if column is VARCHAR

          2. Create a functional index on the cast expression:
               CREATE INDEX CONCURRENTLY ON <table> (CAST(column AS target_type));

          3. Avoid casting in WHERE — use the same type on both sides.

          In Ecto, if you see this with fragment queries:
               where: fragment("CAST(? AS text)", u.status) == ^"active"
             rewrite as:
               where: u.status == ^:active  # cast the param, not the column
          """,
          entry: entry,
          details: %{
            field: field_name,
            expression: text,
            label: label,
            node_type: node.node_type,
            relation: node.relation_name
          }
        }
      end
    end)
    |> Enum.uniq_by(fn v -> {v.details.field, v.details.expression} end)
  end
end
