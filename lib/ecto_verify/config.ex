defmodule EctoVerify.Config do
  @moduledoc """
  Configuration for EctoVerify.

  Built from options passed to `EctoVerify.setup/1` and stored in
  application env for access from the `EctoVerify.Case` macro.
  """

  @default_rules [
    # EXPLAIN-based rules (run after each test)
    EctoVerify.Rules.SequentialScan,
    EctoVerify.Rules.SortWithoutIndex,
    EctoVerify.Rules.HashJoinSpill,
    EctoVerify.Rules.IndexFilterRatio,
    EctoVerify.Rules.CartesianJoin,
    # Cross-query rules (run after each test, no EXPLAIN needed)
    EctoVerify.Rules.NPlusOne,
    # Static SQL text rules (run after each test, no DB needed)
    EctoVerify.Rules.MissingLimit,
    EctoVerify.Rules.OrderWithoutLimit,
    EctoVerify.Rules.NonSargable,
    EctoVerify.Rules.UnparameterizedQuery,
    EctoVerify.Rules.SelectStar,
    EctoVerify.Rules.NotInSubquery,
    EctoVerify.Rules.OffsetPagination,
    # EXPLAIN-based rules (additional)
    EctoVerify.Rules.SortSpillToDisk,
    EctoVerify.Rules.PlannerEstimationError,
    EctoVerify.Rules.ImplicitCast,
    # Cross-query rules (additional)
    EctoVerify.Rules.RedundantQuery,
    # Schema-level rules (run once per suite, query pg_catalog)
    EctoVerify.Rules.MissingFkIndex,
    EctoVerify.Rules.IndexCount,
    EctoVerify.Rules.SerialOverflow,
    # Suite-end rules (snapshot before → compare after all tests)
    EctoVerify.Rules.UnusedIndexes,
    # Migration-level rules (AST analysis of priv/repo/migrations/*.exs)
    EctoVerify.Rules.MigrationIndexNotConcurrent,
    EctoVerify.Rules.MigrationColumnNotNull,
    EctoVerify.Rules.MigrationFkNotValid,
    EctoVerify.Rules.MigrationChangeColumnType
  ]

  @default_thresholds %{
    seq_scan_min_rows: 100,
    sort_min_rows: 100,
    n_plus_one: 5,
    max_indexes: 10,
    index_filter_ratio: 10,
    # Ratio of actual_rows / plan_rows (or inverse) to flag planner estimation errors
    estimation_error_ratio: 10
  }

  @default_filter_parameters [:password, :token, :secret, :key, :api_key, :private_key]

  defstruct repos: [],
            rules: @default_rules,
            thresholds: @default_thresholds,
            output: :ansi,
            filter_parameters: @default_filter_parameters

  @type output_mode :: :ansi | :plain | :silent

  @type t :: %__MODULE__{
          repos: [module()],
          rules: [module()],
          thresholds: map(),
          output: output_mode(),
          filter_parameters: [atom()]
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    ignore = Keyword.get(opts, :ignore_rules, [])

    rules =
      case Keyword.get(opts, :rules, :all) do
        :all -> @default_rules
        list when is_list(list) -> list
      end
      |> Enum.reject(&(&1 in ignore))

    user_thresholds =
      opts
      |> Keyword.get(:thresholds, [])
      |> Map.new()

    %__MODULE__{
      repos: Keyword.fetch!(opts, :repos),
      rules: rules,
      thresholds: Map.merge(@default_thresholds, user_thresholds),
      output: Keyword.get(opts, :output, :ansi),
      filter_parameters: Keyword.get(opts, :filter_parameters, @default_filter_parameters)
    }
  end

  @spec store(t()) :: :ok
  def store(%__MODULE__{} = config) do
    Application.put_env(:ecto_verify, :config, config)
  end

  @spec get() :: t() | nil
  def get do
    Application.get_env(:ecto_verify, :config)
  end

  @spec default_rules() :: [module()]
  def default_rules, do: @default_rules
end
