defmodule PrzmaWeb.ActivityChannel do
  @moduledoc """
  Channel for real-time activity updates.

  Topics:
  - activity:user:USER_ID - User's personal activity feed
  - activity:tenant:TENANT_ID - All activities in tenant
  - activity:member:MEMBER_ID - Specific member's activities
  """

  use PrzmaWeb, :channel

  alias Przma.ActivityStreams
  alias Przma.AuditLog

  @impl true
  def join("activity:user:" <> user_id, _params, socket) do
    if authorized?(socket, user_id) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("activity:tenant:" <> tenant_id, _params, socket) do
    if socket.assigns.tenant_id == tenant_id do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("activity:member:" <> member_id, _params, socket) do
    if authorized_for_member?(socket, member_id) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Send recent activities on join
    push(socket, "presence_state", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_in("get_recent", %{"limit" => limit}, socket) do
    tenant_id = socket.assigns.tenant_id

    case ActivityStreams.get_activities(tenant_id, %{limit: limit}) do
      {:ok, activities} ->
        {:reply, {:ok, %{activities: activities}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("create", %{"text" => text}, socket) do
    tenant_id = socket.assigns.tenant_id
    user_id = socket.assigns.user_id

    case ActivityStreams.parse_natural_language(text, user_id, tenant_id) do
      {:ok, activity} ->
        # Enqueue for enrichment
        Przma.ActivityStreams.Pipeline.enqueue_activity(activity)

        # Broadcast to channel
        broadcast!(socket, "new_activity", %{activity: activity})

        {:reply, {:ok, %{activity: activity}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("subscribe", %{"filters" => filters}, socket) do
    # Store filters in socket assigns for filtering broadcasts
    socket = assign(socket, :filters, filters)
    {:reply, {:ok, %{subscribed: true}}, socket}
  end

  # Private Functions

  defp authorized?(socket, user_id) do
    socket.assigns.user_id == user_id
  end

  defp authorized_for_member?(socket, member_id) do
    tenant_id = socket.assigns.tenant_id
    # Check if member belongs to user's tenant
    case Przma.Accounts.get_member(member_id, tenant_id) do
      {:ok, _member} -> true
      _ -> false
    end
  end
end
