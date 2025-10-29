defmodule Przma.Release do
  @moduledoc """
  Release tasks for PRZMA deployment.

  Run migrations, setup, etc.
  """

  @app :przma

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def setup do
    load_app()

    # Create databases
    for repo <- repos() do
      case repo.__adapter__.storage_up(repo.config) do
        :ok -> IO.puts("Database created for #{inspect(repo)}")
        {:error, :already_up} -> IO.puts("Database already exists for #{inspect(repo)}")
        {:error, term} -> IO.puts("Error creating database: #{inspect(term)}")
      end
    end

    # Run migrations
    migrate()

    # Setup CouchDB
    setup_couchdb()

    # Seed data if needed
    # seed()
  end

  def seed do
    load_app()

    # Run seed scripts
    seed_path = Path.join([:code.priv_dir(@app), "repo", "seeds.exs"])

    if File.exists?(seed_path) do
      Code.eval_file(seed_path)
      IO.puts("Seeding complete")
    else
      IO.puts("No seed file found")
    end
  end

  defp setup_couchdb do
    couchdb_url = Application.get_env(@app, :couchdb_url)
    {user, pass} = Application.get_env(@app, :couchdb_credentials)

    IO.puts("Setting up CouchDB at #{couchdb_url}")

    # Verify CouchDB is accessible
    case HTTPoison.get(couchdb_url, [], [hackney: [basic_auth: {user, pass}]]) do
      {:ok, %{status_code: 200}} ->
        IO.puts("CouchDB is accessible")
        :ok

      error ->
        IO.puts("Failed to connect to CouchDB: #{inspect(error)}")
        {:error, :couchdb_not_accessible}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
