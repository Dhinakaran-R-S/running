defmodule Przma.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      
      add :id, :binary_id, primary_key: true
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :username, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :tenant_id, :binary_id
      add :status, :string, default: "active"
      add :deleted_at, :utc_datetime
      add :is_active, :boolean, default: true
      add :is_verified, :boolean, default: false
      add :auth_provider, :string, default: "local"
      add :failed_login_attempts, :integer, default: 0
      add :last_login_at, :utc_datetime
      add :password_changed_at, :utc_datetime
      add :mfa_enabled, :boolean, default: false
      add :mfa_secret, :string

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:email])
  end
end
