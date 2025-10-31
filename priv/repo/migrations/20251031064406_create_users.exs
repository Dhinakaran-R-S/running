defmodule Przma.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :tenant_id, :binary_id
      add :status, :string, default: "active"
      add :mfa_enabled, :boolean, default: false
      add :mfa_secret, :string

      timestamps()
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:email])
  end
end
