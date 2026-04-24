defmodule EctoSpect.Config do
  @moduledoc """
  Configuration for EctoSpect.

  Built from options passed to `EctoSpect.setup/1` and stored in
  application env for access from the `EctoSpect.Case` macro.
  """

  @default_rules [
    # EXPLAIN-based rules (run after each test)
    EctoSpect.Rules.SequentialScan,
    EctoSpect.Rules.SortWithoutIndex,
    EctoSpect.Rules.HashJoinSpill,
    EctoSpect.Rules.IndexFilterRatio,
    EctoSpect.Rules.CartesianJoin,
    # Cross-query rules (run after each test, no EXPLAIN needed)
    EctoSpect.Rules.NPlusOne,
    # Static SQL text rules (run after each test, no DB needed)
    EctoSpect.Rules.MissingLimit,
    EctoSpect.Rules.OrderWithoutLimit,
    EctoSpect.Rules.NonSargable,
    EctoSpect.Rules.UnparameterizedQuery,
    EctoSpect.Rules.SelectStar,
    EctoSpect.Rules.NotInSubquery,
    EctoSpect.Rules.OffsetPagination,
    # EXPLAIN-based rules (additional)
    EctoSpect.Rules.SortSpillToDisk,
    EctoSpect.Rules.PlannerEstimationError,
    EctoSpect.Rules.ImplicitCast,
    # Cross-query rules (additional)
    EctoSpect.Rules.RedundantQuery,
    # Schema-level rules (run once per suite, query pg_catalog)
    EctoSpect.Rules.MissingFkIndex,
    EctoSpect.Rules.IndexCount,
    EctoSpect.Rules.SerialOverflow,
    # Suite-end rules (snapshot before → compare after all tests)
    EctoSpect.Rules.UnusedIndexes,
    # Migration-level rules (AST analysis of priv/repo/migrations/*.exs)
    EctoSpect.Rules.MigrationIndexNotConcurrent,
    EctoSpect.Rules.MigrationColumnNotNull,
    EctoSpect.Rules.MigrationFkNotValid,
    EctoSpect.Rules.MigrationChangeColumnType
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
    Application.put_env(:ecto_spect, :config, config)
  end

  @spec get() :: t() | nil
  def get do
    Application.get_env(:ecto_spect, :config)
  end

  @spec default_rules() :: [module()]
  def default_rules, do: @default_rules
end
