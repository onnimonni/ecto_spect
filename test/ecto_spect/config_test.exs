defmodule EctoSpect.ConfigTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Config

  describe "new/1" do
    test "requires repos" do
      assert_raise KeyError, fn ->
        Config.new([])
      end
    end

    test "uses all default rules when rules: :all" do
      config = Config.new(repos: [MyApp.Repo])
      assert config.rules == Config.default_rules()
    end

    test "accepts explicit rule list" do
      config = Config.new(repos: [MyApp.Repo], rules: [EctoSpect.Rules.SequentialScan])
      assert config.rules == [EctoSpect.Rules.SequentialScan]
    end

    test "respects ignore_rules" do
      config =
        Config.new(
          repos: [MyApp.Repo],
          ignore_rules: [EctoSpect.Rules.MissingLimit]
        )

      refute EctoSpect.Rules.MissingLimit in config.rules
      assert EctoSpect.Rules.SequentialScan in config.rules
    end

    test "merges threshold overrides" do
      config = Config.new(repos: [MyApp.Repo], thresholds: [seq_scan_min_rows: 50])
      assert config.thresholds.seq_scan_min_rows == 50
      # Other defaults preserved
      assert config.thresholds.n_plus_one == 5
    end

    test "defaults to ansi output" do
      config = Config.new(repos: [MyApp.Repo])
      assert config.output == :ansi
    end
  end
end
