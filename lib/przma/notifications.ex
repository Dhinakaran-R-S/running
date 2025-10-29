defmodule Przma.Notifications do
  @moduledoc """
  The Notifications context for managing multi-channel notifications.

  Supports:
  - Email notifications
  - In-app notifications
  - Push notifications
  - Webhook notifications
  """

  alias Przma.Repo
  alias Przma.Schemas.Member
  alias PrzmaWeb.Endpoint

  @doc """
  Sends a notification to a member.
  """
  def send_notification(member_id, type, data) do
    with {:ok, member} <- get_member(member_id),
         preferences <- get_notification_preferences(member) do

      # Send via enabled channels
      if preferences.email_enabled do
        send_email_notification(member, type, data)
      end

      if preferences.push_enabled do
        send_push_notification(member, type, data)
      end

      # Always send in-app notification
      send_in_app_notification(member, type, data)

      :ok
    end
  end

  @doc """
  Sends an in-app notification via WebSocket.
  """
  def send_in_app_notification(member, type, data) do
    payload = %{
      type: type,
      data: data,
      timestamp: DateTime.utc_now()
    }

    Endpoint.broadcast("member:#{member.id}", "notification", payload)
  end

  @doc """
  Sends an email notification.
  """
  def send_email_notification(member, type, data) do
    # Queue email sending via Oban
    %{
      member_id: member.id,
      type: type,
      data: data
    }
    |> Przma.Workers.EmailWorker.new()
    |> Oban.insert()
  end

  @doc """
  Sends a push notification.
  """
  def send_push_notification(member, type, data) do
    # Queue push notification via Oban
    %{
      member_id: member.id,
      type: type,
      data: data
    }
    |> Przma.Workers.PushNotificationWorker.new()
    |> Oban.insert()
  end

  @doc """
  Broadcasts notification to entire organization.
  """
  def broadcast_to_organization(organization_id, type, data) do
    Endpoint.broadcast("activity:tenant:#{organization_id}", "notification", %{
      type: type,
      data: data,
      timestamp: DateTime.utc_now()
    })
  end

  # Private Functions

  defp get_member(member_id) do
    case Repo.get(Member, member_id) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  defp get_notification_preferences(member) do
    # Get from member metadata or use defaults
    preferences = member.metadata["notification_preferences"] || %{}

    %{
      email_enabled: Map.get(preferences, "email_enabled", true),
      push_enabled: Map.get(preferences, "push_enabled", true),
      in_app_enabled: Map.get(preferences, "in_app_enabled", true)
    }
  end
end
