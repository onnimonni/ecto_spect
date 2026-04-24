defmodule EctoSpect.Formatter do
  @moduledoc """
  Formats `EctoSpect.Violation` structs as Credo-style terminal output.

  Supports `:ansi` (colored) and `:plain` output modes.
  """

  @separator String.duplicate("─", 58)

  @doc "Print violations for a test to stderr."
  @spec print([EctoSpect.Violation.t()], keyword()) :: :ok
  def print(violations, config \\ %EctoSpect.Config{})

  def print([], _config), do: :ok

  def print(violations, %EctoSpect.Config{output: :silent}), do: violations && :ok

  def print(violations, config) do
    use_color = match?(%EctoSpect.Config{output: :ansi}, config) and IO.ANSI.enabled?()
    count = length(violations)
    label = if count == 1, do: "violation", else: "violations"

    header = "\nEctoSpect found #{count} #{label}:\n"

    IO.puts(
      :stderr,
      if(use_color, do: IO.ANSI.yellow() <> header <> IO.ANSI.reset(), else: header)
    )

    violations
    |> Enum.each(&print_violation(&1, use_color))

    :ok
  end

  @doc "Print schema-level violations (index count, etc.) once per suite."
  @spec print_schema([EctoSpect.Violation.t()], map()) :: :ok
  def print_schema([], _config), do: :ok

  def print_schema(violations, config) do
    use_color = match?(%EctoSpect.Config{output: :ansi}, config) and IO.ANSI.enabled?()
    header = "\nEctoSpect schema warnings:\n"

    IO.puts(
      :stderr,
      if(use_color, do: IO.ANSI.yellow() <> header <> IO.ANSI.reset(), else: header)
    )

    Enum.each(violations, &print_violation(&1, use_color))
  end

  @doc "Build a one-line summary for ExUnit assertion error message."
  @spec summary([EctoSpect.Violation.t()]) :: String.t()
  def summary(violations) do
    lines =
      violations
      |> Enum.map(fn v ->
        prefix = if v.severity == :error, do: "[E]", else: "[W]"
        "#{prefix} #{v.message} (#{v.rule |> Module.split() |> List.last()})"
      end)

    "EctoSpect: " <> Enum.join(lines, ", ")
  end

  defp print_violation(v, use_color) do
    {severity_label, color} =
      case v.severity do
        :error -> {"[E]", IO.ANSI.red()}
        :warning -> {"[W]", IO.ANSI.yellow()}
      end

    rule_name = v.rule |> Module.split() |> Enum.join(".")

    header =
      if use_color do
        color <>
          "  #{severity_label} #{v.message}" <>
          IO.ANSI.reset() <>
          IO.ANSI.faint() <> " — #{rule_name}" <> IO.ANSI.reset()
      else
        "  #{severity_label} #{v.message} — #{rule_name}"
      end

    IO.puts(:stderr, header)
    IO.puts(:stderr, "")

    # Query
    if sql = v.entry[:sql] do
      IO.puts(:stderr, "  Query:")
      IO.puts(:stderr, "    #{String.trim(sql)}")
      IO.puts(:stderr, "")
    end

    # Advice
    advice_lines =
      v.advice
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&("    " <> String.trim_trailing(&1)))
      |> Enum.join("\n")

    IO.puts(:stderr, "  Advice:")
    IO.puts(:stderr, advice_lines)
    IO.puts(:stderr, "")

    # Caller from stacktrace
    if caller = format_caller(v.entry[:stacktrace]) do
      IO.puts(:stderr, "  Caller: #{caller}")
      IO.puts(:stderr, "")
    end

    IO.puts(:stderr, "  #{@separator}")
    IO.puts(:stderr, "")
  end

  defp format_caller(nil), do: nil
  defp format_caller([]), do: nil

  defp format_caller(stacktrace) do
    # Find the first frame that is not from Ecto/EctoSpect internals
    stacktrace
    |> Enum.find(fn
      {mod, _fun, _arity, info} ->
        mod_str = inspect(mod)

        not String.starts_with?(mod_str, "Ecto") and
          not String.starts_with?(mod_str, "EctoSpect") and
          not String.starts_with?(mod_str, "DBConnection") and
          not String.starts_with?(mod_str, "Postgrex") and
          Keyword.has_key?(info, :file)

      _ ->
        false
    end)
    |> case do
      {_mod, _fun, _arity, info} ->
        file = Keyword.get(info, :file, "unknown")
        line = Keyword.get(info, :line, 0)
        "#{file}:#{line}"

      nil ->
        nil
    end
  end
end
