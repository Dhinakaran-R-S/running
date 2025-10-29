defmodule PrzmaWeb.AuthView do
  @moduledoc """
  JSON view for authentication responses.
  """
  
  use PrzmaWeb, :view
  
  def render("tokens.json", %{tokens: tokens, user: user}) do
    %{
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_type: tokens.token_type,
      expires_in: tokens.expires_in,
      user: render_user(user)
    }
  end
  
  def render("tokens.json", %{tokens: tokens}) do
    %{
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_type: tokens.token_type,
      expires_in: tokens.expires_in
    }
  end
  
  def render("user.json", %{user: user}) do
    %{data: render_user(user)}
  end
  
  defp render_user(user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      tenant_id: user.tenant_id,
      status: user.status,
      mfa_enabled: user.mfa_enabled,
      roles: render_roles(user),
      created_at: user.inserted_at
    }
  end
  
  defp render_roles(user) do
    case Map.get(user, :roles) do
      nil -> []
      roles when is_list(roles) -> Enum.map(roles, & &1.name)
      _ -> []
    end
  end
end
