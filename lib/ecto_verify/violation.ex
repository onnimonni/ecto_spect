defmodule EctoVerify.Violation do
  @moduledoc """
  Represents a single rule violation found during query analysis.
  """

  @enforce_keys [:rule, :message, :advice, :entry]
  defstruct [:rule, :message, :advice, :entry, :severity, :details]

  @type severity :: :error | :warning

  @type t :: %__MODULE__{
          rule: module(),
          message: String.t(),
          advice: String.t(),
          entry: map(),
          severity: severity(),
          details: map() | nil
        }
end
