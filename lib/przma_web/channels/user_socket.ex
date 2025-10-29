defmodule PrzmaWeb.UserSocket do
  @moduledoc """
  WebSocket connection handler with authentication and tenant isolation.
  """

  use Phoenix.Socket

  alias Przma.Auth.Token

  # Channels
  channel "activity:*", PrzmaWeb.ActivityChannel
  channel "conversation:*", PrzmaWeb.ConversationChannel
  channel "member:*", PrzmaWeb.MemberChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Token.verify_access_token(token) do
      {:ok, claims} ->
        socket = socket
        |> assign(:user_id, claims["sub"])
        |> assign(:tenant_id, claims["tenant_id"])
        |> assign(:roles, claims["roles"])
        |> assign(:session_id, claims["sid"])

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
