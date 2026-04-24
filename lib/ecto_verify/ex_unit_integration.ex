defmodule EctoVerify.Case do
  @moduledoc """
  ExUnit integration for EctoVerify.

  Add to test modules to enable automatic query analysis:

      defmodule MyApp.AccountsTest do
        use ExUnit.Case, async: true
        use EctoVerify.Case, repo: MyApp.Repo

        test "lists active users" do
          # Queries are captured automatically.
          # After the test, EctoVerify runs EXPLAIN and checks rules.
          # If violations are found, the test fails with a detailed message.
        end
      end

  ## Options

  - `:repo` — (required) the `Ecto.Repo` module for this test module.
    Used to open the dedicated EXPLAIN connection.

  ## Schema checks

  Index count and other schema-level checks run **once per test suite** (not per
  module) and print warnings to stderr without failing individual tests. They
  represent global database design issues rather than per-query problems.

  ## Composability

  `use EctoVerify.Case` is designed to compose with your existing `DataCase`:

      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate

        using do
          quote do
            use EctoVerify.Case, repo: MyApp.Repo
            # ... rest of DataCase setup
          end
        end
      end
  """

  defmacro __using__(opts) do
    quote do
      setup_all do
        config = EctoVerify.Config.get()

        if config do
          repo = unquote(opts)[:repo] || hd(config.repos)

          case EctoVerify.ExplainRunner.open_connection(repo) do
            {:ok, conn} ->
              # Schema-level checks run once per suite (not per module).
              # ETS insert_new is atomic — safe with async: true test modules.
              schema_run? =
                :ets.info(:ecto_verify_schema_run) == :undefined or
                  not :ets.insert_new(:ecto_verify_schema_run, {:done, true})

              unless schema_run? do
                schema_rules =
                  Enum.filter(config.rules, &function_exported?(&1, :check_schema, 2))

                schema_violations =
                  Enum.flat_map(schema_rules, & &1.check_schema(conn, config.thresholds))

                if schema_violations != [] do
                  EctoVerify.Formatter.print_schema(schema_violations, config)
                end
              end

              on_exit(fn ->
                EctoVerify.ExplainRunner.close_connection(conn)
              end)

              {:ok, ecto_verify_conn: conn, ecto_verify_config: config}

            {:error, reason} ->
              require Logger

              Logger.warning(
                "[EctoVerify] Could not open EXPLAIN connection: #{inspect(reason)}. " <>
                  "Query analysis disabled for this module."
              )

              {:ok, ecto_verify_conn: nil, ecto_verify_config: config}
          end
        else
          {:ok, ecto_verify_conn: nil, ecto_verify_config: nil}
        end
      end

      setup %{ecto_verify_conn: conn, ecto_verify_config: config} = _context do
        if conn && config do
          test_pid = self()
          EctoVerify.QueryStore.register(test_pid)

          # Mark this process as an active test so the telemetry handler captures
          Process.put(:ecto_verify_active, true)

          on_exit(fn ->
            entries = EctoVerify.QueryStore.take_for(test_pid)

            if entries != [] do
              # Group-level checks (N+1, etc.) — no EXPLAIN needed
              group_violations =
                config.rules
                |> Enum.filter(&function_exported?(&1, :check_group, 2))
                |> Enum.flat_map(& &1.check_group(entries, config.thresholds))

              # EXPLAIN-based checks — one EXPLAIN per captured query
              explain_violations = EctoVerify.ExplainRunner.explain_all(conn, entries, config)

              all_violations = group_violations ++ explain_violations

              if all_violations != [] do
                EctoVerify.Formatter.print(all_violations, config)

                raise ExUnit.AssertionError,
                  message: EctoVerify.Formatter.summary(all_violations)
              end
            end
          end)
        end

        :ok
      end
    end
  end
end
