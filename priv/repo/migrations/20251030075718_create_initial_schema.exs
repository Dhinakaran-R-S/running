defmodule Przma.Repo.Migrations.CreateInitialSchema do
  @moduledoc """
  Initial database schema migration for PRZMA platform.

  Creates all core tables with proper indexes and constraints.
  """

  use Ecto.Migration

  def up do
    # Enable extensions
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
    execute "CREATE EXTENSION IF NOT EXISTS \"pgcrypto\""
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Create enum types
    create_enums()

    # Create tables
    create_organizations()
    create_members()
    create_roles_and_permissions()
    create_activities()
    create_conversations_and_messages()
    create_auth_tables()
    create_audit_logs()
    create_cas_objects()

    # Create indexes
    create_indexes()
  end

  def down do
    drop table(:cas_objects)
    drop table(:audit_logs)
    drop table(:refresh_tokens)
    drop table(:sessions)
    drop table(:messages)
    drop table(:conversation_participants)
    drop table(:conversations)
    drop table(:activities)
    drop table(:member_roles)
    drop table(:role_permissions)
    drop table(:permissions)
    drop table(:roles)
    drop table(:members)
    drop table(:organizations)

    # Drop enum types
    execute "DROP TYPE IF EXISTS org_plan"
    execute "DROP TYPE IF EXISTS org_status"
    execute "DROP TYPE IF EXISTS member_status"
    execute "DROP TYPE IF EXISTS conversation_status"
    execute "DROP TYPE IF EXISTS message_role"
    execute "DROP TYPE IF EXISTS session_status"
    execute "DROP TYPE IF EXISTS audit_severity"
    execute "DROP TYPE IF EXISTS audit_status"
  end

  defp create_enums do
    execute """
    CREATE TYPE org_plan AS ENUM ('free', 'basic', 'professional', 'enterprise')
    """

    execute """
    CREATE TYPE org_status AS ENUM ('active', 'suspended', 'cancelled')
    """

    execute """
    CREATE TYPE member_status AS ENUM ('active', 'inactive', 'suspended')
    """

    execute """
    CREATE TYPE conversation_status AS ENUM ('active', 'archived', 'ended')
    """

    execute """
    CREATE TYPE message_role AS ENUM ('user', 'assistant', 'system')
    """

    execute """
    CREATE TYPE session_status AS ENUM ('active', 'expired', 'revoked')
    """

    execute """
    CREATE TYPE audit_severity AS ENUM ('info', 'warning', 'critical')
    """

    execute """
    CREATE TYPE audit_status AS ENUM ('success', 'failure')
    """
  end

  defp create_organizations do
    create table(:organizations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :name, :string, null: false
      add :slug, :string, null: false
      add :email, :string, null: false
      add :plan, :org_plan, default: "free", null: false
      add :status, :org_status, default: "active", null: false
      add :settings, :jsonb, default: "{}"
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create unique_index(:organizations, [:slug])
    create unique_index(:organizations, [:email])
    create index(:organizations, [:status])
  end

  defp create_members do
    create table(:members, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :email, :string, null: false
      add :username, :string
      add :status, :member_status, default: "active", null: false
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:members, [:organization_id])
    create unique_index(:members, [:organization_id, :email])
    create unique_index(:members, [:organization_id, :username])
  end

  defp create_roles_and_permissions do
    create table(:roles, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :name, :string, null: false
      add :description, :text
      add :level, :integer, default: 0

      timestamps()
    end

    create unique_index(:roles, [:name])

    create table(:permissions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :name, :string, null: false
      add :description, :text
      add :resource, :string, null: false
      add :action, :string, null: false

      timestamps()
    end

    create unique_index(:permissions, [:name])
    create index(:permissions, [:resource, :action])

    create table(:role_permissions, primary_key: false) do
      add :role_id, references(:roles, type: :uuid, on_delete: :delete_all), null: false
      add :permission_id, references(:permissions, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:role_permissions, [:role_id, :permission_id])

    create table(:member_roles, primary_key: false) do
      add :member_id, references(:members, type: :uuid, on_delete: :delete_all), null: false
      add :role_id, references(:roles, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:member_roles, [:member_id, :role_id])
  end

  defp create_activities do
    create table(:activities, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all), null: false
      add :actor_id, :uuid, null: false
      add :type, :string, default: "Activity"
      add :verb, :string, null: false
      add :object, :jsonb, null: false
      add :target, :jsonb
      add :published, :timestamptz, null: false

      # Framework mappings
      add :preserve, {:array, :string}, default: []
      add :seven_p, {:array, :string}, default: []

      # AI enrichment
      add :perception_enrichment, :jsonb
      add :synthesis, :jsonb
      add :embedding, :vector, size: 1536

      # Metadata
      add :context, :jsonb, default: "{}"
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:activities, [:organization_id])
    create index(:activities, [:actor_id])
    create index(:activities, [:verb])
    create index(:activities, [:published])
    create index(:activities, [:organization_id, :actor_id, :published])

    # Vector similarity index
    execute """
    CREATE INDEX activities_embedding_idx
    ON activities
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100)
    """
  end

  defp create_conversations_and_messages do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all), null: false
      add :initiated_by_id, references(:members, type: :uuid, on_delete: :nilify_all)
      add :ended_by_id, references(:members, type: :uuid, on_delete: :nilify_all)
      add :topic, :string
      add :status, :conversation_status, default: "active", null: false
      add :context, :jsonb, default: "{}"
      add :metadata, :jsonb, default: "{}"
      add :ended_at, :timestamptz

      timestamps()
    end

    create index(:conversations, [:organization_id])
    create index(:conversations, [:status])
    create index(:conversations, [:inserted_at])

    create table(:conversation_participants, primary_key: false) do
      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all), null: false
      add :member_id, references(:members, type: :uuid, on_delete: :delete_all), null: false
      add :joined_at, :timestamptz, default: fragment("NOW()")

      timestamps()
    end

    create unique_index(:conversation_participants, [:conversation_id, :member_id])

    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :conversation_id, references(:conversations, type: :uuid, on_delete: :delete_all), null: false
      add :member_id, references(:members, type: :uuid, on_delete: :nilify_all)
      add :role, :message_role, default: "user", null: false
      add :content, :text, null: false
      add :content_type, :string, default: "text"
      add :metadata, :jsonb, default: "{}"
      add :sent_at, :timestamptz, null: false

      timestamps()
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:member_id])
    create index(:messages, [:sent_at])
  end

  defp create_auth_tables do
    create table(:sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :user_id, :uuid, null: false
      add :token_hash, :string, null: false
      add :ip_address, :string
      add :user_agent, :text
      add :device_id, :string
      add :status, :session_status, default: "active", null: false
      add :last_active_at, :timestamptz
      add :expires_at, :timestamptz, null: false
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:sessions, [:user_id])
    create index(:sessions, [:token_hash])
    create index(:sessions, [:status])
    create index(:sessions, [:expires_at])

    create table(:refresh_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :token, :string, null: false
      add :user_id, :uuid, null: false
      add :session_id, :uuid, null: false
      add :expires_at, :timestamptz, null: false
      add :revoked_at, :timestamptz

      timestamps(updated_at: false)
    end

    create unique_index(:refresh_tokens, [:token])
    create index(:refresh_tokens, [:user_id])
    create index(:refresh_tokens, [:expires_at])
  end

  defp create_audit_logs do
    create table(:audit_logs, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
      add :tenant_id, :uuid, null: false
      add :user_id, :uuid
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :uuid
      add :ip_address, :string
      add :user_agent, :text
      add :session_id, :uuid
      add :severity, :audit_severity, default: "info", null: false
      add :status, :audit_status, default: "success", null: false
      add :metadata, :jsonb, default: "{}"
      add :changes, :jsonb
      add :timestamp, :timestamptz, null: false

      timestamps(updated_at: false)
    end

    create index(:audit_logs, [:tenant_id])
    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:resource_type, :resource_id])
    create index(:audit_logs, [:timestamp])
    create index(:audit_logs, [:severity])
    create index(:audit_logs, [:tenant_id, :timestamp])
  end

  defp create_cas_objects do
    create table(:cas_objects, primary_key: false) do
      add :hash, :string, primary_key: true
      add :tenant_id, :uuid, null: false
      add :size, :bigint, null: false
      add :mime_type, :string
      add :filename, :string
      add :storage_type, :string, null: false
      add :metadata, :jsonb, default: "{}"
      add :reference_count, :integer, default: 1

      timestamps(updated_at: false)
    end

    create index(:cas_objects, [:tenant_id])
    create index(:cas_objects, [:tenant_id, :hash])
  end

  defp create_indexes do
    # Add any additional composite indexes here
    execute """
    CREATE INDEX activities_org_actor_verb_idx
    ON activities(organization_id, actor_id, verb)
    """

    execute """
    CREATE INDEX activities_preserve_idx
    ON activities USING GIN (preserve)
    """

    execute """
    CREATE INDEX activities_seven_p_idx
    ON activities USING GIN (seven_p)
    """
  end
end
