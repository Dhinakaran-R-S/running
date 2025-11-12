defmodule Przma.Accounts do
  @moduledoc """
  The Accounts context for managing users, members, and organizations.
  """

  import Ecto.Query, warn: false
  alias Przma.Repo
  alias Przma.Schemas.{Organization, Member}
  alias Przma.Auth.{User, Role}

  # ============================================================================
  # ORGANIZATIONS
  # ============================================================================

  @doc """
  Creates an organization.
  """
  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_organization(any()) :: {:error, :not_found} | {:ok, any()}
  @doc """
  Gets an organization by ID.
  """
  def get_organization(id) do
    case Repo.get(Organization, id) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Gets an organization by slug.
  """
  def get_organization_by_slug(slug) do
    case Repo.get_by(Organization, slug: slug) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  @doc """
  Updates an organization.
  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an organization (soft delete by changing status).
  """
  def delete_organization(%Organization{} = organization) do
    update_organization(organization, %{status: :cancelled})
  end

  # ============================================================================
  # MEMBERS
  # ============================================================================

  @doc """
  Lists all members for an organization.
  """
  def list_members(organization_id, filters \\ %{}) do
    query = from m in Member,
      where: m.organization_id == ^organization_id,
      order_by: [desc: m.inserted_at]

    query
    |> apply_member_filters(filters)
    |> limit(^Map.get(filters, :limit, 100))
    |> Repo.all()
  end

  @doc """
  Gets a member by ID within an organization.
  """
  def get_member(id, organization_id) do
    case Repo.get_by(Member, id: id, organization_id: organization_id) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  @doc """
  Gets a member by email within an organization.
  """
  def get_member_by_email(email, organization_id) do
    case Repo.get_by(Member, email: email, organization_id: organization_id) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  @doc """
  Creates a member.
  """
  def create_member(attrs \\ %{}) do
    %Member{}
    |> Member.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a member.
  """
  def update_member(%Member{} = member, attrs) do
    member
    |> Member.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a member (soft delete).
  """
  def delete_member(%Member{} = member) do
    update_member(member, %{status: :inactive})
  end

  @doc """
  Updates member roles.
  """
  def update_member_roles(%Member{} = member, role_names) when is_list(role_names) do
    roles = from(r in Role, where: r.name in ^role_names)
    |> Repo.all()

    member
    |> Repo.preload(:roles)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:roles, roles)
    |> Repo.update()
  end

  @doc """
  Invites a new member to an organization.
  """
  def invite_member(organization_id, email, role) do
    # Check if member already exists
    case get_member_by_email(email, organization_id) do
      {:ok, _member} ->
        {:error, :already_member}

      {:error, :not_found} ->
        # Create invitation token and send email
        token = generate_invitation_token()

        # Store invitation
        invitation = %{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          email: email,
          role: role,
          token: token,
          expires_at: DateTime.utc_now() |> DateTime.add(7 * 24 * 3600, :second)
        }

        # Send invitation email
        # Przma.Mailer.send_invitation(invitation)

        {:ok, invitation}
    end
  end

  @doc """
  Gets activity summary for a member.
  """
  def get_activity_summary(member_id, organization_id) do
    # Get activity counts by verb
    activity_counts = from(a in Przma.Schemas.Activity,
      where: a.actor_id == ^member_id and a.organization_id == ^organization_id,
      group_by: a.verb,
      select: {a.verb, count(a.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})

    # Get recent activities
    recent_activities = from(a in Przma.Schemas.Activity,
      where: a.actor_id == ^member_id and a.organization_id == ^organization_id,
      order_by: [desc: a.published],
      limit: 10
    )
    |> Repo.all()

    # Get PRESERVE coverage
    preserve_coverage = from(a in Przma.Schemas.Activity,
      where: a.actor_id == ^member_id and a.organization_id == ^organization_id,
      select: fragment("ARRAY_AGG(DISTINCT unnest(?))", a.preserve)
    )
    |> Repo.one()
    |> case do
      nil -> []
      preserve -> preserve |> Enum.uniq()
    end

    # Get 7P coverage
    seven_p_coverage = from(a in Przma.Schemas.Activity,
      where: a.actor_id == ^member_id and a.organization_id == ^organization_id,
      select: fragment("ARRAY_AGG(DISTINCT unnest(?))", a.seven_p)
    )
    |> Repo.one()
    |> case do
      nil -> []
      seven_p -> seven_p |> Enum.uniq()
    end

    %{
      total_activities: Enum.sum(Map.values(activity_counts)),
      activity_counts: activity_counts,
      recent_activities: recent_activities,
      preserve_coverage: preserve_coverage,
      seven_p_coverage: seven_p_coverage
    }
  end

  # ============================================================================
  # USERS (Auth)
  # ============================================================================

  @doc """
  Gets a user by ID.
  """
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, Repo.preload(user, :roles)}
    end
  end

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) do
    case Repo.get_by(User, username: username) do
      nil -> {:error, :not_found}
      user -> {:ok, Repo.preload(user, :roles)}
    end
  end

  @doc """
Authenticates a user by username and password.
"""
  def authenticate_user(username, password) do
    case Repo.get_by(User, username: username) do
      nil ->
        {:error, :user_not_found}

      user ->
        if Pbkdf2.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_password}
        end
    end
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    case Repo.get_by(User, email: email) do
      nil -> {:error, :not_found}
      user -> {:ok, Repo.preload(user, :roles)}
    end
  end

  # Private Functions

  defp apply_member_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, q -> from m in q, where: m.status == ^status
      {:role, _role}, q -> q  # TODO: Join with roles
      _, q -> q
    end)
  end

  defp generate_invitation_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
