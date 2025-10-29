defmodule PrzmaWeb.ConversationChannel do
  @moduledoc """
  Channel for real-time conversation/messaging.

  Topics:
  - conversation:CONVERSATION_ID - Specific conversation messages
  """

  use PrzmaWeb, :channel

  alias Przma.Conversations

  @impl true
  def join("conversation:" <> conversation_id, _params, socket) do
    tenant_id = socket.assigns.tenant_id

    case Conversations.get_conversation(conversation_id, tenant_id) do
      {:ok, conversation} ->
        if user_in_conversation?(socket.assigns.user_id, conversation) do
          socket = assign(socket, :conversation_id, conversation_id)
          send(self(), :after_join)
          {:ok, socket}
        else
          {:error, %{reason: "not_a_participant"}}
        end

      {:error, :not_found} ->
        {:error, %{reason: "conversation_not_found"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Mark user as present
    push(socket, "presence_state", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_message", %{"content" => content}, socket) do
    conversation_id = socket.assigns.conversation_id
    user_id = socket.assigns.user_id

    case Conversations.create_message(conversation_id, user_id, %{content: content}) do
      {:ok, message} ->
        # Broadcast to all participants
        broadcast!(socket, "new_message", %{message: message})

        {:reply, {:ok, %{message: message}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("typing", %{"typing" => typing}, socket) do
    user_id = socket.assigns.user_id

    broadcast_from!(socket, "user_typing", %{
      user_id: user_id,
      typing: typing
    })

    {:noreply, socket}
  end

  def handle_in("get_messages", %{"limit" => limit, "before" => before_id}, socket) do
    conversation_id = socket.assigns.conversation_id

    case Conversations.get_messages(conversation_id, %{limit: limit, before: before_id}) do
      {:ok, messages} ->
        {:reply, {:ok, %{messages: messages}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Private Functions

  defp user_in_conversation?(user_id, conversation) do
    Enum.any?(conversation.participants, fn participant ->
      participant.id == user_id
    end)
  end
end
