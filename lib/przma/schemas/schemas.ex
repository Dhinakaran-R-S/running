defmodule Przma.Schemas.Organization do
  @moduledoc """
  Organization (tenant) schema.
  Each organization has complete data isolation.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :email, :string
    field :plan, Ecto.Enum, values: [:free, :basic, :professional, :enterprise], default: :free
    field :status, Ecto.Enum, values: [:active, :suspended, :cancelled], default: :active
    field :settings, :map, default: %{}
    field :metadata, :map, default: %{}
    
    has_many :members, Przma.Schemas.Member
    has_many :activities, Przma.Schemas.Activity
    
    timestamps()
  end
  
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :email, :plan, :status, :settings, :metadata])
    |> validate_required([:name, :slug, :email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:slug)
    |> unique_constraint(:email)
  end
end

defmodule Przma.Schemas.Member do
  @moduledoc """
  Member (user) schema within an organization.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "members" do
    field :name, :string
    field :email, :string
    field :username, :string
    field :status, Ecto.Enum, values: [:active, :inactive, :suspended], default: :active
    field :metadata, :map, default: %{}
    
    belongs_to :organization, Przma.Schemas.Organization
    many_to_many :roles, Przma.Auth.Role, join_through: "member_roles"
    has_many :activities, Przma.Schemas.Activity, foreign_key: :actor_id
    
    timestamps()
  end
  
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :email, :username, :organization_id, :status, :metadata])
    |> validate_required([:name, :email, :organization_id])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint([:email, :organization_id])
    |> unique_constraint([:username, :organization_id])
  end
end

defmodule Przma.Schemas.Activity do
  @moduledoc """
  ActivityStreams 2.0 activity schema.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "activities" do
    field :type, :string, default: "Activity"
    field :actor_id, :binary_id
    field :verb, :string
    field :object, :map
    field :target, :map
    field :published, :utc_datetime
    
    # Framework mappings
    field :preserve, {:array, :string}, default: []
    field :seven_p, {:array, :string}, default: []
    
    # AI enrichment
    field :perception_enrichment, :map
    field :synthesis, :map
    field :embedding, Pgvector.Ecto.Vector
    
    # Metadata
    field :context, :map, default: %{}
    field :metadata, :map, default: %{}
    
    belongs_to :organization, Przma.Schemas.Organization
    
    timestamps()
  end
  
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:type, :actor_id, :verb, :object, :target, :published, 
                    :preserve, :seven_p, :context, :metadata, :organization_id])
    |> validate_required([:actor_id, :verb, :object, :published, :organization_id])
    |> validate_inclusion(:verb, get_valid_verbs())
  end
  
  defp get_valid_verbs do
    ~w(attend learn create complete achieve share reflect meet teach practice
       read write watch listen exercise invest save earn purchase improve
       plan organize meditate help support contribute give collaborate)
  end
end

defmodule Przma.Schemas.Conversation do
  @moduledoc """
  Conversation schema for messaging.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "conversations" do
    field :topic, :string
    field :status, Ecto.Enum, values: [:active, :archived, :ended], default: :active
    field :context, :map, default: %{}
    field :metadata, :map, default: %{}
    field :ended_at, :utc_datetime
    
    belongs_to :organization, Przma.Schemas.Organization
    belongs_to :initiated_by, Przma.Schemas.Member
    belongs_to :ended_by, Przma.Schemas.Member
    
    has_many :messages, Przma.Schemas.Message
    many_to_many :participants, Przma.Schemas.Member, join_through: "conversation_participants"
    
    timestamps()
  end
  
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:topic, :status, :context, :metadata, :organization_id, 
                    :initiated_by_id, :ended_by_id, :ended_at])
    |> validate_required([:organization_id, :initiated_by_id])
  end
end

defmodule Przma.Schemas.Message do
  @moduledoc """
  Message schema within a conversation.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "messages" do
    field :role, Ecto.Enum, values: [:user, :assistant, :system], default: :user
    field :content, :string
    field :content_type, :string, default: "text"
    field :metadata, :map, default: %{}
    field :sent_at, :utc_datetime
    
    belongs_to :conversation, Przma.Schemas.Conversation
    belongs_to :member, Przma.Schemas.Member
    
    timestamps()
  end
  
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :content_type, :metadata, :sent_at, 
                    :conversation_id, :member_id])
    |> validate_required([:content, :conversation_id, :sent_at])
    |> validate_length(:content, max: 10000)
  end
end

defmodule Przma.Auth.Role do
  @moduledoc """
  Role schema for RBAC.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "roles" do
    field :name, :string
    field :description, :string
    field :level, :integer, default: 0
    
    many_to_many :permissions, Przma.Auth.PermissionSchema, join_through: "role_permissions"
    
    timestamps()
  end
  
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :level])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end

defmodule Przma.Auth.PermissionSchema do
  @moduledoc """
  Permission schema for RBAC.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "permissions" do
    field :name, :string
    field :description, :string
    field :resource, :string
    field :action, :string
    
    timestamps()
  end
  
  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:name, :description, :resource, :action])
    |> validate_required([:name, :resource, :action])
    |> unique_constraint(:name)
  end
end

defmodule Przma.Auth.RefreshToken do
  @moduledoc """
  Refresh token storage for revocation support.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  schema "refresh_tokens" do
    field :token, :string
    field :user_id, :binary_id
    field :session_id, :binary_id
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    
    timestamps(updated_at: false)
  end
  
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:token, :user_id, :session_id, :expires_at, :revoked_at])
    |> validate_required([:token, :user_id, :session_id, :expires_at])
    |> unique_constraint(:token)
  end
end
