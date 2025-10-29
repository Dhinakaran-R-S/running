defmodule PrzmaWeb.MemberController do
  @moduledoc """
  Controller for managing family members/users within a tenant.
  """
  
  use PrzmaWeb, :controller
  
  alias Przma.Accounts
  alias Przma.AuditLog
  alias PrzmaWeb.ErrorView
  
  action_fallback PrzmaWeb.FallbackController
  
  @doc """
  List all members in the tenant.
  """
  def index(conn, params) do
    tenant_id = conn.assigns.current_tenant_id
    
    filters = %{
      status: params["status"],
      role: params["role"],
      limit: String.to_integer(params["limit"] || "50")
    }
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.into(%{})
    
    members = Accounts.list_members(tenant_id, filters)
    
    render(conn, "index.json", members: members)
  end
  
  @doc """
  Get a specific member.
  """
  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    
    case Accounts.get_member(id, tenant_id) do
      {:ok, member} ->
        render(conn, "show.json", member: member)
      
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Member not found")
    end
  end
  
  @doc """
  Create a new member.
  """
  def create(conn, %{"member" => member_params}) do
    tenant_id = conn.assigns.current_tenant_id
    current_user = conn.assigns.current_user
    
    params = Map.put(member_params, "tenant_id", tenant_id)
    
    case Accounts.create_member(params) do
      {:ok, member} ->
        # Log member creation
        AuditLog.log_action(current_user, :create_member, :member, member.id, %{
          ip_address: get_client_ip(conn)
        })
        
        conn
        |> put_status(:created)
        |> render("show.json", member: member)
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Update a member.
  """
  def update(conn, %{"id" => id, "member" => member_params}) do
    tenant_id = conn.assigns.current_tenant_id
    current_user = conn.assigns.current_user
    
    with {:ok, member} <- Accounts.get_member(id, tenant_id),
         {:ok, updated_member} <- Accounts.update_member(member, member_params) do
      
      # Log member update
      AuditLog.log_action(current_user, :update_member, :member, member.id, %{
        ip_address: get_client_ip(conn),
        changes: member_params
      })
      
      render(conn, "show.json", member: updated_member)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Member not found")
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Delete a member (soft delete).
  """
  def delete(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    current_user = conn.assigns.current_user
    
    with {:ok, member} <- Accounts.get_member(id, tenant_id),
         :ok <- Accounts.delete_member(member) do
      
      # Log member deletion
      AuditLog.log_action(current_user, :delete_member, :member, member.id, %{
        ip_address: get_client_ip(conn)
      })
      
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Member not found")
    end
  end
  
  @doc """
  Get member's activity summary.
  """
  def activity_summary(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    
    with {:ok, member} <- Accounts.get_member(id, tenant_id) do
      summary = Accounts.get_activity_summary(member.id, tenant_id)
      
      json(conn, summary)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Member not found")
    end
  end
  
  @doc """
  Update member roles.
  """
  def update_roles(conn, %{"id" => id, "roles" => roles}) do
    tenant_id = conn.assigns.current_tenant_id
    current_user = conn.assigns.current_user
    
    with {:ok, member} <- Accounts.get_member(id, tenant_id),
         {:ok, updated_member} <- Accounts.update_member_roles(member, roles) do
      
      # Log role update
      AuditLog.log_action(current_user, :update_member_roles, :member, member.id, %{
        ip_address: get_client_ip(conn),
        changes: %{roles: roles}
      })
      
      render(conn, "show.json", member: updated_member)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Member not found")
      
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", error: reason)
    end
  end
  
  @doc """
  Invite a new member via email.
  """
  def invite(conn, %{"email" => email, "role" => role}) do
    tenant_id = conn.assigns.current_tenant_id
    current_user = conn.assigns.current_user
    
    case Accounts.invite_member(tenant_id, email, role) do
      {:ok, invitation} ->
        # Log invitation
        AuditLog.log_action(current_user, :invite_member, :invitation, invitation.id, %{
          ip_address: get_client_ip(conn),
          metadata: %{email: email, role: role}
        })
        
        json(conn, %{message: "Invitation sent", invitation_id: invitation.id})
      
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", error: reason)
    end
  end
  
  # Private Functions
  
  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end
end
