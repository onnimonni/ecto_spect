defmodule Mix.Tasks.EctoSpect.Install do
  @moduledoc """
  Installs EctoSpect into the current Phoenix/Ecto project.

      $ mix ecto_spect.install

  Or via igniter:

      $ mix igniter.install ecto_spect

  ## What it does

  1. Inserts `EctoSpect.setup/1` before `ExUnit.start()` in `test/test_helper.exs`
  2. Adds `use EctoSpect.Case` inside the `quote do` block of your `DataCase`
     (detected automatically from `test/support/data_case.ex`)
  """
  @shortdoc "Installs EctoSpect into a Phoenix/Ecto project"

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ecto_spect,
      example: "mix ecto_spect.install",
      schema: [repo: :string],
      aliases: [r: :repo]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    repo = detect_repo(igniter, opts[:repo])

    igniter
    |> patch_test_helper(repo)
    |> patch_data_case(repo)
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp detect_repo(igniter, nil) do
    app = Igniter.Project.Application.app_name(igniter)

    app_camel =
      app
      |> Atom.to_string()
      |> Macro.camelize()

    Module.concat([app_camel, "Repo"])
  end

  defp detect_repo(_igniter, repo_string) when is_binary(repo_string) do
    Module.concat([repo_string])
  end

  defp patch_test_helper(igniter, repo) do
    Igniter.update_elixir_file(igniter, "test/test_helper.exs", fn zipper ->
      setup_call = "EctoSpect.setup(repos: [#{inspect(repo)}])\n"

      case find_node(zipper, &exunit_start?/1) do
        nil ->
          # No ExUnit.start() found — append to end
          {:ok, Igniter.Code.Common.add_code(zipper, setup_call)}

        target ->
          {:ok, Igniter.Code.Common.add_code(target, setup_call, placement: :before)}
      end
    end)
  end

  defp patch_data_case(igniter, repo) do
    path = "test/support/data_case.ex"

    if File.exists?(path) do
      Igniter.update_elixir_file(igniter, path, fn zipper ->
        use_line = "use EctoSpect.Case, repo: #{inspect(repo)}"

        # Navigate into the first `quote do` block (inside `using do`)
        case find_node(zipper, &quote_do?/1) do
          nil ->
            # No quote block — leave unchanged
            {:ok, zipper}

          quote_zipper ->
            # Check if already installed
            already_installed =
              find_node(quote_zipper, fn node ->
                match?(
                  {:use, _, [{:__aliases__, _, [:EctoSpect, :Case]} | _]},
                  node
                )
              end)

            if already_installed do
              {:ok, zipper}
            else
              inner = Sourceror.Zipper.down(quote_zipper)

              if inner do
                {:ok, Igniter.Code.Common.add_code(inner, use_line, placement: :before)}
              else
                {:ok, zipper}
              end
            end
        end
      end)
    else
      Igniter.add_warning(
        igniter,
        "Could not find test/support/data_case.ex. " <>
          "Add `use EctoSpect.Case, repo: #{inspect(repo)}` manually inside your DataCase `using` block."
      )
    end
  end

  # Find first node matching predicate via depth-first traversal
  defp find_node(zipper, predicate) do
    Sourceror.Zipper.find(zipper, predicate)
  end

  # Matches: ExUnit.start() or ExUnit.start(opts)
  defp exunit_start?({:., _, [{:__aliases__, _, [:ExUnit]}, :start]}), do: true
  defp exunit_start?({{:., _, [{:__aliases__, _, [:ExUnit]}, :start]}, _, _}), do: true
  defp exunit_start?(_), do: false

  # Matches: quote do ... end
  defp quote_do?({:quote, _, [[do: _]]}), do: true
  defp quote_do?({:quote, _, [_, [do: _]]}), do: true
  defp quote_do?(_), do: false
end
