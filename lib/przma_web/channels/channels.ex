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
