defmodule EctoVerify.Rules.MigrationChangeColumnType do
  @moduledoc """
  Detects column type changes in migrations.

  Changing a column's type with `ALTER COLUMN ... TYPE` rewrites the entire table
  in most cases, acquiring an `ACCESS EXCLUSIVE` lock that blocks ALL reads and
  writes. This is one of the most dangerous operations in PostgreSQL.

  Safe type changes (no rewrite): widening varchar, numeric to same or larger,
  integer to bigint on PostgreSQL 14+ (in some cases).

  Unsafe: text → varchar, varchar → integer, timestamp → timestamptz, etc.

  The safe pattern is to add a new column, backfill, switch the application,
  then drop the old column — or use a view alias during the transition.

  Migration-level check: runs once per test suite via AST analysis.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "migration-change-column-type"

  @impl true
  def description,
    do: "Detects column type changes — rewrites entire table and blocks all reads/writes"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_migration(ast, _source, path) do
    {_, violations} =
      Macro.postwalk(ast, [], fn node, acc ->
        case node do
          # modify :col, :new_type — changing type
          {:modify, meta, [col, new_type | _opts]} when is_atom(new_type) ->
            v = build_violation(path, meta[:line], col, new_type)
            {node, [v | acc]}

          _ ->
            {node, acc}
        end
      end)

    Enum.reverse(violations)
  end

  defp build_violation(path, line, col, new_type) do
    col_name = if is_atom(col), do: col, else: inspect(col)
    location = format_location(path, line)

    %EctoVerify.Violation{
      rule: __MODULE__,
      severity: :error,
      message:
        "Column `#{col_name}` type changed to `#{new_type}` at #{location} — full table rewrite",
      advice: """
      Changing a column type rewrites the entire table with an ACCESS EXCLUSIVE lock,
      blocking all reads and writes for the duration of the rewrite.

      Safe zero-downtime approach:

        # Step 1: Add new column (nullable)
        add :#{col_name}_new, :#{new_type}

        # Step 2 (separate deploy): Backfill in batches
        execute "UPDATE table SET #{col_name}_new = #{col_name}::#{new_type} WHERE id BETWEEN $1 AND $2"

        # Step 3: Rename columns atomically (rename is metadata-only, instant)
        rename table(:source), :#{col_name}, to: :#{col_name}_old
        rename table(:source), :#{col_name}_new, to: :#{col_name}

        # Step 4 (later): Drop old column
        remove :#{col_name}_old

      Safe widening exceptions (no table rewrite):
        - INTEGER → BIGINT (PostgreSQL 14+ in some cases, always safe for new data)
        - varchar(N) → varchar(M) where M > N
        - char(N) → text

      Always test with EXPLAIN on a production-size copy first.
      """,
      entry: %{sql: "(migration check)", source: path, params: [], stacktrace: nil},
      details: %{path: path, line: line, column: col_name, new_type: new_type}
    }
  end

  defp format_location(path, nil), do: Path.basename(path)
  defp format_location(path, line), do: "#{Path.basename(path)}:#{line}"
end
