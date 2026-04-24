defmodule EctoVerify.MigrationChecker do
  @moduledoc """
  Parses Ecto migration files as Elixir AST and runs migration-level rules.

  Uses `Code.string_to_quoted!/1` (the same approach as excellent_migrations)
  to parse each `.exs` file in the configured repo's migrations directory,
  then passes the AST to rules implementing `check_migration/3`.

  Migration checks run once per test suite (in `EctoVerify.setup/1`) and
  report violations after all tests complete.
  """

  require Logger

  @doc """
  Run migration checks for all repos in the config.
  Returns a flat list of violations across all migration files.
  """
  @spec check(EctoVerify.Config.t()) :: [EctoVerify.Violation.t()]
  def check(%EctoVerify.Config{repos: repos, rules: rules}) do
    migration_rules = Enum.filter(rules, &function_exported?(&1, :check_migration, 3))

    if migration_rules == [] do
      []
    else
      repos
      |> Enum.flat_map(&migration_files_for/1)
      |> Enum.flat_map(&check_file(&1, migration_rules))
    end
  end

  defp migration_files_for(repo) do
    path =
      if function_exported?(Ecto.Migrator, :migrations_path, 1) do
        Ecto.Migrator.migrations_path(repo)
      else
        # Fallback: derive from repo module name
        app = repo |> Module.split() |> hd() |> Macro.underscore() |> String.to_existing_atom()
        Application.app_dir(app, "priv/repo/migrations")
      end

    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".exs"))
        |> Enum.sort()
        |> Enum.map(&Path.join(path, &1))

      {:error, reason} ->
        Logger.debug("[EctoVerify] MigrationChecker: cannot list #{path}: #{inspect(reason)}")

        []
    end
  end

  defp check_file(path, rules) do
    source = File.read!(path)

    ast =
      try do
        Code.string_to_quoted!(source, file: path)
      rescue
        e ->
          Logger.debug("[EctoVerify] MigrationChecker: failed to parse #{path}: #{inspect(e)}")

          nil
      end

    if ast do
      Enum.flat_map(rules, fn rule ->
        try do
          rule.check_migration(ast, source, path)
        rescue
          e ->
            Logger.debug(
              "[EctoVerify] MigrationChecker: #{rule} failed on #{path}: #{inspect(e)}"
            )

            []
        end
      end)
    else
      []
    end
  end
end
