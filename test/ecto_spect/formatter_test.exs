defmodule EctoSpect.FormatterTest do
  use ExUnit.Case, async: true

  alias EctoSpect.Formatter

  defp violation(opts \\ []) do
    %EctoSpect.Violation{
      rule: EctoSpect.Rules.SequentialScan,
      severity: Keyword.get(opts, :severity, :error),
      message: Keyword.get(opts, :message, "Seq scan on users touching 500 rows"),
      advice: "Add an index.",
      entry: %{sql: "SELECT * FROM users", stacktrace: nil},
      details: %{}
    }
  end

  describe "summary/1" do
    test "formats single error violation" do
      result = Formatter.summary([violation(severity: :error)])
      assert String.starts_with?(result, "EctoSpect: ")
      assert String.contains?(result, "[E]")
      assert String.contains?(result, "SequentialScan")
    end

    test "formats single warning violation" do
      result = Formatter.summary([violation(severity: :warning)])
      assert String.contains?(result, "[W]")
    end

    test "joins multiple violations with comma" do
      v1 = violation(severity: :error, message: "First issue")
      v2 = violation(severity: :warning, message: "Second issue")
      result = Formatter.summary([v1, v2])
      assert String.contains?(result, "[E]")
      assert String.contains?(result, "[W]")
      assert String.contains?(result, ", ")
    end

    test "includes rule short name (last module segment)" do
      result = Formatter.summary([violation()])
      assert String.contains?(result, "SequentialScan")
      refute String.contains?(result, "EctoSpect.Rules.SequentialScan")
    end

    test "includes violation message" do
      result = Formatter.summary([violation(message: "Custom message here")])
      assert String.contains?(result, "Custom message here")
    end
  end

  describe "print/2 with :silent output" do
    test "returns :ok without printing" do
      config = %EctoSpect.Config{output: :silent}
      assert :ok = Formatter.print([violation()], config)
    end
  end

  describe "print/2 with empty list" do
    test "returns :ok immediately" do
      assert :ok = Formatter.print([], %EctoSpect.Config{})
    end
  end

  describe "print_schema/2" do
    test "returns :ok for empty list" do
      assert :ok = Formatter.print_schema([], %EctoSpect.Config{output: :plain})
    end
  end
end
