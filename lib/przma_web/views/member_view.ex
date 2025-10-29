defmodule PrzmaWeb.MemberView do
  @moduledoc """
  JSON view for member/user resources.
  """
  
  use PrzmaWeb, :view
  
  alias PrzmaWeb.MemberView
  
  def render("index.json", %{members: members}) do
    %{
      data: render_many(members, MemberView, "member.json"),
      count: length(members)
    }
  end
  
  def render("show.json", %{member: member}) do
    %{data: render_one(member, MemberView, "member.json")}
  end
  
  def render("member.json", %{member: member}) do
    %{
      id: member.id,
      name: member.name,
      email: member.email,
      tenant_id: member.tenant_id,
      status: member.status,
      roles: render_roles(member),
      metadata: member.metadata || %{},
      created_at: member.inserted_at,
      updated_at: member.updated_at
    }
  end
  
  defp render_roles(member) do
    case Map.get(member, :roles) do
      nil -> []
      roles when is_list(roles) -> Enum.map(roles, & &1.name)
      _ -> []
    end
  end
end

defmodule PrzmaWeb.ErrorView do
  @moduledoc """
  JSON view for error responses.
  """
  
  use PrzmaWeb, :view
  
  def render("error.json", %{error: error}) when is_binary(error) do
    %{error: %{message: error}}
  end
  
  def render("error.json", %{error: error}) when is_atom(error) do
    %{error: %{message: to_string(error)}}
  end
  
  def render("error.json", %{changeset: changeset}) do
    %{error: %{
      message: "Validation failed",
      errors: translate_errors(changeset)
    }}
  end
  
  def render("500.json", _assigns) do
    %{error: %{message: "Internal server error"}}
  end
  
  def render("404.json", _assigns) do
    %{error: %{message: "Not found"}}
  end
  
  def render("403.json", _assigns) do
    %{error: %{message: "Forbidden"}}
  end
  
  def render("401.json", _assigns) do
    %{error: %{message: "Unauthorized"}}
  end
  
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
