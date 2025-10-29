defmodule Przma.Auth.Permission do
  @moduledoc """
  Permission checking and management.
  """

  import Ecto.Query
  alias Przma.Repo

  def user_has_permission?(user, permission) when is_binary(permission) do
    query = from u in Przma.Auth.User,
      join: ur in "user_roles", on: ur.user_id == u.id,
      join: r in Przma.Auth.Role, on: r.id == ur.role_id,
      join: rp in "role_permissions", on: rp.role_id == r.id,
      join: p in Przma.Auth.PermissionSchema, on: p.id == rp.permission_id,
      where: u.id == ^user.id and p.name == ^permission,
      select: count(p.id)

    Repo.one(query) > 0
  end
end
