defmodule PrzmaWeb.MemberChannel do
  @moduledoc """
  Channel for member-specific notifications and updates.

  Topics:
  - member:MEMBER_ID - Personal notifications and updates
  """

  use PrzmaWeb, :channel

  @impl true
  def join("member:" <> member_id, _params, socket) do
    if socket.assigns.user_id == member_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{pong: true}}, socket}
  end
end
