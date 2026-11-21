defmodule ShoddyBot.Authz.Grant do
  @moduledoc "A permission, install-wide (`tenant: nil`) or bound to one tenant."
  defstruct [:permission, :tenant]

  @type t :: %__MODULE__{
          permission: ShoddyBot.Authz.Permission.t(),
          tenant: nil | %{id: Ecto.UUID.t(), schema: String.t()}
        }
end
