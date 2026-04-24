defmodule EctoSpect.Rule do
  @moduledoc """
  Behaviour that every EctoSpect rule implements.

  Rules implement one or more of these callbacks depending on what they need:

  | Callback           | When called               | Use for                         |
  |--------------------|---------------------------|---------------------------------|
  | `check/3`          | After each test           | EXPLAIN plan analysis           |
  | `check_group/2`    | After each test           | Cross-query analysis (e.g. N+1) |
  | `check_schema/2`   | Once (first test module)  | Schema-level checks             |
  | `setup_suite/1`    | Before any test runs      | Capture baseline state          |
  | `check_suite_end/2`| After all tests complete  | Compare state, suite violations |
  | `check_migration/3`| Once per suite (setup)   | AST analysis of migration files |

  All callbacks are optional. A rule may implement any combination.
  """

  @type entry :: %{
          sql: String.t(),
          params: list(),
          cast_params: list(),
          source: String.t() | nil,
          stacktrace: list() | nil,
          repo: module(),
          total_time_us: non_neg_integer() | nil
        }

  @type plan_nodes :: [map()]

  @callback name() :: String.t()
  @callback description() :: String.t()

  @doc "Check a single query's EXPLAIN plan nodes for violations."
  @callback check(plan_nodes(), entry(), thresholds :: map()) :: [EctoSpect.Violation.t()]

  @doc "Check all queries captured in a test for cross-query violations (e.g. N+1)."
  @callback check_group(entries :: [entry()], thresholds :: map()) :: [EctoSpect.Violation.t()]

  @doc "Check schema-level issues using a dedicated DB connection. Called once per suite."
  @callback check_schema(conn :: pid(), thresholds :: map()) :: [EctoSpect.Violation.t()]

  @doc """
  Called once before any tests run. Use to snapshot baseline DB state.
  The same connection is passed to `check_suite_end/2` at the end.
  """
  @callback setup_suite(conn :: pid()) :: :ok

  @doc """
  Called once after all tests complete. Use to compare state against the
  baseline captured in `setup_suite/1` and return suite-level violations.
  """
  @callback check_suite_end(conn :: pid(), thresholds :: map()) :: [EctoSpect.Violation.t()]

  @doc """
  Called once per suite to check an Ecto migration file's AST for unsafe patterns.
  `ast` is the result of `Code.string_to_quoted!/1`, `source` is the raw file
  contents, `path` is the absolute file path.
  """
  @callback check_migration(ast :: Macro.t(), source :: String.t(), path :: String.t()) ::
              [EctoSpect.Violation.t()]

  @optional_callbacks check: 3,
                      check_group: 2,
                      check_schema: 2,
                      setup_suite: 1,
                      check_suite_end: 2,
                      check_migration: 3
end
