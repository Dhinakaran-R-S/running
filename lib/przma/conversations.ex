defmodule Przma.Conversations do
  @moduledoc """
  The Conversations context for managing conversations and messages.
  """

  import Ecto.Query, warn: false
  alias Przma.Repo
  alias Przma.Schemas.{Conversation, Message, Member}
  alias PrzmaWeb.Endpoint

  # ============================================================================
  # CONVERSATIONS
  # ============================================================================

  @doc """
  Lists conversations for an organization.
  """
  def list_conversations(organization_id, filters \\ %{}) do
    query = from c in Conversation,
      where: c.organization_id == ^organization_id,
      order_by: [desc: c.inserted_at],
      preload: [:participants, :initiated_by]

    query
    |> apply_conversation_filters(filters)
    |> limit(^Map.get(filters, :limit, 50))
    |> Repo.all()
  end

  @doc """
  Gets a conversation by ID.
  """
  def get_conversation(id, organization_id) do
    case Repo.get_by(Conversation, id: id, organization_id: organization_id) do
      nil -> {:error, :not_found}
      conversation -> {:ok, Repo.preload(conversation, [:participants, :messages])}
    end
  end

  @doc """
  Creates a conversation.
  """
  def create_conversation(attrs \\ %{}) do
    result = %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()

    case result do
      {:ok, conversation} ->
        # Add initiated_by as first participant
        if attrs["initiated_by_id"] do
          add_participant(conversation.id, attrs["initiated_by_id"])
        end

        # Broadcast creation
        broadcast_conversation_event(conversation.organization_id, "conversation_created", conversation)

        {:ok, conversation}

      error -> error
    end
  end

  @doc """
  Updates a conversation.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Ends a conversation.
  """
  def end_conversation(%Conversation{} = conversation, ended_by_id) do
    update_conversation(conversation, %{
      status: :ended,
      ended_by_id: ended_by_id,
      ended_at: DateTime.utc_now()
    })
  end

  @doc """
  Archives a conversation.
  """
  def archive_conversation(%Conversation{} = conversation) do
    update_conversation(conversation, %{status: :archived})
  end

  @doc """
  Adds a participant to a conversation.
  """
  def add_participant(conversation_id, member_id) do
    Repo.insert_all("conversation_participants", [
      %{
        conversation_id: conversation_id,
        member_id: member_id,
        joined_at: DateTime.utc_now(),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ], on_conflict: :nothing)

    # Broadcast participant joined
    broadcast_to_conversation(conversation_id, "participant_joined", %{member_id: member_id})

    :ok
  end

  @doc """
  Removes a participant from a conversation.
  """
  def remove_participant(conversation_id, member_id) do
    from(cp in "conversation_participants",
      where: cp.conversation_id == ^conversation_id and cp.member_id == ^member_id
    )
    |> Repo.delete_all()

    # Broadcast participant left
    broadcast_to_conversation(conversation_id, "participant_left", %{member_id: member_id})

    :ok
  end

  # ============================================================================
  # MESSAGES
  # ============================================================================

  @doc """
  Lists messages in a conversation.
  """
  def get_messages(conversation_id, filters \\ %{}) do
    query = from m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [desc: m.sent_at],
      preload: [:member]

    query
    |> apply_message_filters(filters)
    |> limit(^Map.get(filters, :limit, 50))
    |> Repo.all()
    |> Enum.reverse()  # Return in chronological order
    |> then(&{:ok, &1})
  end

  @doc """
  Creates a message in a conversation.
  """
  def create_message(conversation_id, member_id, attrs \\ %{}) do
    attrs = attrs
    |> Map.put(:conversation_id, conversation_id)
    |> Map.put(:member_id, member_id)
    |> Map.put(:sent_at, DateTime.utc_now())

    result = %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()

    case result do
      {:ok, message} ->
        message = Repo.preload(message, [:member, :conversation])

        # Broadcast to conversation
        broadcast_to_conversation(conversation_id, "new_message", %{
          id: message.id,
          content: message.content,
          role: message.role,
          member: %{
            id: message.member.id,
            name: message.member.name
          },
          sent_at: message.sent_at
        })

        # Update conversation timestamp
        update_conversation_timestamp(conversation_id)

        # Process AI enrichment if needed
        if should_enrich_message?(message) do
          enqueue_message_enrichment(message)
        end

        {:ok, message}

      error -> error
    end
  end

  @doc """
  Gets a message by ID.
  """
  def get_message(id) do
    case Repo.get(Message, id) do
      nil -> {:error, :not_found}
      message -> {:ok, Repo.preload(message, [:member, :conversation])}
    end
  end

  @doc """
  Generates AI response for a conversation.
  """
  def generate_ai_response(conversation_id) do
    with {:ok, conversation} <- get_conversation(conversation_id, nil),
         {:ok, messages} <- get_messages(conversation_id, %{limit: 10}) do

      # Build context from recent messages
      context = Enum.map(messages, fn msg ->
        %{
          role: msg.role,
          content: msg.content
        }
      end)

      # Generate response using AI
      case Przma.AI.LocalInference.chat_completion(context) do
        {:ok, response} ->
          # Create assistant message
          create_message(conversation_id, nil, %{
            role: :assistant,
            content: response
          })

        error -> error
      end
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp apply_conversation_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, q -> from c in q, where: c.status == ^status
      {:participant_id, id}, q ->
        from c in q,
          join: p in "conversation_participants",
          on: p.conversation_id == c.id,
          where: p.member_id == ^id
      _, q -> q
    end)
  end

  defp apply_message_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:before, message_id}, q ->
        subquery = from m in Message, where: m.id == ^message_id, select: m.sent_at
        from m in q, where: m.sent_at < subquery(subquery)

      {:after, message_id}, q ->
        subquery = from m in Message, where: m.id == ^message_id, select: m.sent_at
        from m in q, where: m.sent_at > subquery(subquery)

      {:role, role}, q -> from m in q, where: m.role == ^role
      _, q -> q
    end)
  end

  defp update_conversation_timestamp(conversation_id) do
    from(c in Conversation, where: c.id == ^conversation_id)
    |> Repo.update_all(set: [updated_at: DateTime.utc_now()])
  end

  defp broadcast_to_conversation(conversation_id, event, payload) do
    Endpoint.broadcast("conversation:#{conversation_id}", event, payload)
  end

  defp broadcast_conversation_event(organization_id, event, conversation) do
    Endpoint.broadcast("activity:tenant:#{organization_id}", event, %{
      conversation: conversation
    })
  end

  defp should_enrich_message?(message) do
    # Only enrich user messages in active conversations
    message.role == :user &&
    message.conversation.status == :active
  end

  defp enqueue_message_enrichment(message) do
    # Enqueue Oban job for message analysis
    %{message_id: message.id}
    |> Przma.Workers.MessageEnrichmentWorker.new()
    |> Oban.insert()
  end
end
