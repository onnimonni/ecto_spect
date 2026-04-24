defmodule EctoSpect.Rules.MigrationColumnNotNull do
  @moduledoc """
  Detects adding a NOT NULL column without a default value to an existing table.

  Adding a NOT NULL column without a default to a table with existing rows causes
  the migration to fail immediately (existing rows cannot satisfy the constraint).

  PostgreSQL 11+ can add a column with a non-volatile constant default without
  a full table rewrite, but still requires a default to satisfy NOT NULL for
  existing rows.

  Safe pattern:
  1. Add column as nullable first
  2. Backfill values
  3. Add NOT NULL constraint (using NOT VALID + VALIDATE for large tables)

  Migration-level check: runs once per test suite via AST analysis.
  """

  @behaviour EctoSpect.Rule

  @impl true
  def name, do: "migration-column-not-null"

  @impl true
  def description,
    do: "Detects adding NOT NULL columns without a default — fails on non-empty tables"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_migration(ast, _source, path) do
    {_, violations} =
      Macro.postwalk(ast, [], fn node, acc ->
        case node do
          # add :column, :type, null: false — no default
          {:add, meta, [col, _type, opts]} when is_list(opts) ->
            null_false? = Keyword.get(opts, :null, true) == false
            has_default? = Keyword.has_key?(opts, :default)

            if null_false? and not has_default? do
              v = build_violation(path, meta[:line], col)
              {node, [v | acc]}
            else
              {node, acc}
            end

          _ ->
            {node, acc}
        end
      end)

    Enum.reverse(violations)
  end

  defp build_violation(path, line, col) do
    col_name = if is_atom(col), do: col, else: inspect(col)
    location = format_location(path, line)

    %EctoSpect.Violation{
      rule: __MODULE__,
      severity: :error,
      message: "Column `#{col_name}` added with `null: false` but no default at #{location}",
      advice: """
      Adding a NOT NULL column without a default fails immediately if the table
      has existing rows (they cannot satisfy the constraint).

      Safe multi-step approach:
        # Step 1: Add nullable column
        add :#{col_name}, :type

        # Step 2 (separate migration or script): Backfill
        execute "UPDATE table SET #{col_name} = 'value' WHERE #{col_name} IS NULL"

        # Step 3: Add NOT NULL (safe for small tables)
        modify :#{col_name}, :type, null: false

        # For large tables, use NOT VALID + validate separately:
        execute \"\"\"
          ALTER TABLE table
          ADD CONSTRAINT table_#{col_name}_not_null
          CHECK (#{col_name} IS NOT NULL) NOT VALID
        \"\"\"
        # Then in a later migration:
        execute "ALTER TABLE table VALIDATE CONSTRAINT table_#{col_name}_not_null"

      PostgreSQL 11+ allows column addition with a constant non-volatile default
      without a table rewrite — but a default is still required for NOT NULL.
      """,
      entry: %{sql: "(migration check)", source: path, params: [], stacktrace: nil},
      details: %{path: path, line: line, column: col_name}
    }
  end

  defp format_location(path, nil), do: Path.basename(path)
  defp format_location(path, line), do: "#{Path.basename(path)}:#{line}"
end
