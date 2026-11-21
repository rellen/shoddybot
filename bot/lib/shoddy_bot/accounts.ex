defmodule ShoddyBot.Accounts do
  @moduledoc """
  Users and how they sign in. Roles are in `ShoddyBot.Authz`; tenant
  memberships are in `ShoddyBot.Tenancy`.
  """
  use Ash.Domain,
    otp_app: :shoddy_bot

  resources do
    resource ShoddyBot.Accounts.Token
    resource ShoddyBot.Accounts.UserIdentity

    resource ShoddyBot.Accounts.User do
      define :get_user_by_email, action: :get_by_email, args: [:email]
    end
  end

  alias ShoddyBot.Accounts.User

  @doc """
  Returns the user with this email, creating them if they do not exist yet.

  This is internal plumbing that skips authorization: callers must have
  authorized the operation that needs the user (such as adding a member).
  """
  @spec ensure_user(String.t() | Ash.CiString.t()) :: {:ok, User.t()} | {:error, term()}
  def ensure_user(email) do
    case get_user_by_email(email, authorize?: false, not_found_error?: false) do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:ok, nil} ->
        User
        |> Ash.Changeset.for_create(:create_by_email, %{email: email})
        |> Ash.create(authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end
end
