defmodule EctoSpect.Case do
  @moduledoc """
  ExUnit integration for EctoSpect.

  Add to test modules to enable automatic query analysis:

      defmodule MyApp.AccountsTest do
        use ExUnit.Case, async: true
        use EctoSpect.Case, repo: MyApp.Repo

        test "lists active users" do
          # Queries are captured automatically.
          # After the test, EctoSpect runs EXPLAIN and checks rules.
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

  `use EctoSpect.Case` is designed to compose with your existing `DataCase`:

      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate

        using do
          quote do
            use EctoSpect.Case, repo: MyApp.Repo
            # ... rest of DataCase setup
          end
        end
      end
  """

  defmacro __using__(opts) do
    quote do
      setup_all do
        config = EctoSpect.Config.get()

        if config do
          repo = unquote(opts)[:repo] || hd(config.repos)

          case EctoSpect.ExplainRunner.open_connection(repo) do
            {:ok, conn} ->
              # Schema-level checks run once per suite (not per module).
              # ETS insert_new is atomic — safe with async: true test modules.
              schema_run? =
                :ets.info(:ecto_spect_schema_run) == :undefined or
                  not :ets.insert_new(:ecto_spect_schema_run, {:done, true})

              unless schema_run? do
                schema_rules =
                  Enum.filter(config.rules, fn rule ->
                    Code.ensure_loaded?(rule) and function_exported?(rule, :check_schema, 2)
                  end)

                schema_violations =
                  Enum.flat_map(schema_rules, & &1.check_schema(conn, config.thresholds))

                if schema_violations != [] do
                  EctoSpect.Formatter.print_schema(schema_violations, config)
                end
              end

              on_exit(fn ->
                EctoSpect.ExplainRunner.close_connection(conn)
              end)

              {:ok, ecto_spect_conn: conn, ecto_spect_config: config}

            {:error, reason} ->
              require Logger

              Logger.warning(
                "[EctoSpect] Could not open EXPLAIN connection: #{inspect(reason)}. " <>
                  "Query analysis disabled for this module."
              )

              {:ok, ecto_spect_conn: nil, ecto_spect_config: config}
          end
        else
          {:ok, ecto_spect_conn: nil, ecto_spect_config: nil}
        end
      end

      setup %{ecto_spect_conn: conn, ecto_spect_config: config} = _context do
        if conn && config do
          test_pid = self()
          EctoSpect.QueryStore.register(test_pid)

          # Mark this process as an active test so the telemetry handler captures
          Process.put(:ecto_spect_active, true)

          on_exit(fn ->
            entries = EctoSpect.QueryStore.take_for(test_pid)

            if entries != [] do
              # Group-level checks (N+1, etc.) — no EXPLAIN needed.
              # Code.ensure_loaded? forces lazy-loaded rule modules (runtime: false deps)
              # to be available before function_exported? checks them.
              group_violations =
                config.rules
                |> Enum.filter(fn rule ->
                  Code.ensure_loaded?(rule) and function_exported?(rule, :check_group, 2)
                end)
                |> Enum.flat_map(& &1.check_group(entries, config.thresholds))

              # EXPLAIN-based checks — one EXPLAIN per captured query
              explain_violations = EctoSpect.ExplainRunner.explain_all(conn, entries, config)

              all_violations = group_violations ++ explain_violations

              if all_violations != [] do
                EctoSpect.Formatter.print(all_violations, config)

                raise ExUnit.AssertionError,
                  message: EctoSpect.Formatter.summary(all_violations)
              end
            end
          end)
        end

        :ok
      end
    end
  end
end
