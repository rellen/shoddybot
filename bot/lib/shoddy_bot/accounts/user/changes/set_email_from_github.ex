defmodule ShoddyBot.Accounts.User.Changes.SetEmailFromGithub do
  @moduledoc """
  Takes the user's email from a GitHub sign-in, and drops the GitHub OAuth
  tokens.

  The email is GitHub's primary address for the account. It is only accepted
  when GitHub says that address is verified. Otherwise someone could add a
  victim's address to their GitHub account, sign in here first, and own the
  account the victim later reaches by magic link.

  ShoddyBot only uses GitHub to sign people in, so it does not keep the OAuth
  access token. The arguments are replaced with an empty map before the user
  identity is stored, so no token is written to the database.
  """
  use Ash.Resource.Change

  import Shoddy.Strings, only: [is_non_empty_string: 1]

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Changeset.get_argument(changeset, :user_info) || %{}

    changeset = Changeset.set_argument(changeset, :oauth_tokens, %{})

    case user_info do
      %{"email" => email, "email_verified" => true} when is_non_empty_string(email) ->
        Changeset.change_attribute(changeset, :email, email)

      _ ->
        Changeset.add_error(changeset,
          field: :email,
          message: "GitHub did not provide a verified primary email address"
        )
    end
  end
end
