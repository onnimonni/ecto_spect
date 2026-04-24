defmodule EctoVerify.Rules.MigrationFkNotValid do
  @moduledoc """
  Detects foreign key constraints added without `validate: false`.

  Adding a foreign key constraint (via `references/2`) validates ALL existing rows
  immediately, holding a `SHARE ROW EXCLUSIVE` lock on both tables for the full
  validation scan. On large tables this blocks writes and causes downtime.

  The safe pattern is to add the FK with `NOT VALID` (which skips validation of
  existing rows) and then validate it separately in a later migration or with
  `VALIDATE CONSTRAINT` which only holds a weaker lock.

  In Ecto migrations, `validate: false` maps to `NOT VALID`:
    add :user_id, references(:users, validate: false)

  Migration-level check: runs once per test suite via AST analysis.
  """

  @behaviour EctoVerify.Rule

  @impl true
  def name, do: "migration-fk-not-valid"

  @impl true
  def description,
    do: "Detects FK constraints without NOT VALID — validates all rows and blocks writes"

  @impl true
  def check(_nodes, _entry, _thresholds), do: []

  @impl true
  def check_migration(ast, _source, path) do
    {_, violations} =
      Macro.postwalk(ast, [], fn node, acc ->
        case node do
          # add :col, references(:table) — no options list → always flagged
          {:add, meta, [col, {:references, _, [_table]}]} ->
            v = build_violation(path, meta[:line], col)
            {node, [v | acc]}

          # add :col, references(:table, opts) — check for validate: false
          {:add, meta, [col, {:references, _, [_table, opts]}]} when is_list(opts) ->
            if Keyword.get(opts, :validate, true) == false do
              {node, acc}
            else
              v = build_violation(path, meta[:line], col)
              {node, [v | acc]}
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

    %EctoVerify.Violation{
      rule: __MODULE__,
      severity: :error,
      message: "FK on `#{col_name}` added without `validate: false` at #{location}",
      advice: """
      Adding a FK without NOT VALID validates ALL existing rows while holding a
      SHARE ROW EXCLUSIVE lock on both tables — blocking writes during validation.

      Safe two-step approach:

        # Step 1: Add FK without validation (fast, non-blocking)
        add :#{col_name}, references(:target_table, validate: false)

        # Step 2: Validate in a separate migration (uses weaker ShareUpdateExclusiveLock)
        execute "ALTER TABLE source_table VALIDATE CONSTRAINT source_table_#{col_name}_fkey"

      Alternatively with Ecto's constraint DSL:
        alter table(:source_table) do
          add :#{col_name}, references(:target_table, validate: false)
        end
      """,
      entry: %{sql: "(migration check)", source: path, params: [], stacktrace: nil},
      details: %{path: path, line: line, column: col_name}
    }
  end

  defp format_location(path, nil), do: Path.basename(path)
  defp format_location(path, line), do: "#{Path.basename(path)}:#{line}"
end
