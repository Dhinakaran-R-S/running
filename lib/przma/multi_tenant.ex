defmodule Przma.MultiTenant do
  @moduledoc """
  Core multi-tenant management system for PRZMA platform.
  
  Provides complete tenant isolation with:
  - Dedicated CouchDB databases per tenant
  - PostgreSQL schemas per tenant
  - S3 buckets per tenant (CAS, training, models, analytics)
  - Namespace management
  - Resource provisioning and cleanup
  """
  
  use GenServer
  require Logger
  
  @bucket_types [:cas, :training, :models, :analytics, :temporal]
  
  defmodule Tenant do
    defstruct [
      :id,
      :name,
      :slug,
      :email,
      :plan,
      :couchdb_database,
      :postgres_schema,
      :s3_buckets,
      :namespace,
      :created_at,
      :status
    ]
  end
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Create a new tenant with all required resources.
  
  ## Examples
      
      iex> Przma.MultiTenant.create_tenant(%{
      ...>   name: "Acme Corp",
      ...>   slug: "acme_corp",
      ...>   email: "admin@acme.com",
      ...>   plan: "enterprise"
      ...> })
      {:ok, %Tenant{}}
  """
  def create_tenant(attrs) do
    GenServer.call(__MODULE__, {:create_tenant, attrs}, 30_000)
  end
  
  @doc """
  Delete tenant and all associated resources.
  """
  def delete_tenant(tenant_id) do
    GenServer.call(__MODULE__, {:delete_tenant, tenant_id}, 30_000)
  end
  
  @doc """
  Get tenant by ID or slug.
  """
  def get_tenant(identifier) do
    GenServer.call(__MODULE__, {:get_tenant, identifier})
  end
  
  @doc """
  List all tenants with optional filters.
  """
  def list_tenants(filters \\ %{}) do
    GenServer.call(__MODULE__, {:list_tenants, filters})
  end
  
  # Server Callbacks
  
  def init(_opts) do
    state = %{
      tenants: %{},
      tenant_registry: %{}
    }
    
    {:ok, state}
  end
  
  def handle_call({:create_tenant, attrs}, _from, state) do
    case provision_tenant(attrs) do
      {:ok, tenant} ->
        new_state = %{
          state |
          tenants: Map.put(state.tenants, tenant.id, tenant),
          tenant_registry: Map.put(state.tenant_registry, tenant.slug, tenant.id)
        }
        
        Logger.info("Tenant created: #{tenant.slug} (#{tenant.id})")
        {:reply, {:ok, tenant}, new_state}
      
      {:error, reason} ->
        Logger.error("Failed to create tenant: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:delete_tenant, tenant_id}, _from, state) do
    case Map.get(state.tenants, tenant_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      tenant ->
        case cleanup_tenant_resources(tenant) do
          :ok ->
            new_state = %{
              state |
              tenants: Map.delete(state.tenants, tenant_id),
              tenant_registry: Map.delete(state.tenant_registry, tenant.slug)
            }
            
            Logger.info("Tenant deleted: #{tenant.slug}")
            {:reply, :ok, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  def handle_call({:get_tenant, identifier}, _from, state) do
    tenant = case is_binary(identifier) and String.match?(identifier, ~r/^[0-9a-f-]+$/) do
      true -> Map.get(state.tenants, identifier)
      false -> 
        tenant_id = Map.get(state.tenant_registry, identifier)
        Map.get(state.tenants, tenant_id)
    end
    
    {:reply, tenant, state}
  end
  
  def handle_call({:list_tenants, filters}, _from, state) do
    tenants = state.tenants
    |> Map.values()
    |> apply_filters(filters)
    
    {:reply, tenants, state}
  end
  
  # Private Functions
  
  defp provision_tenant(attrs) do
    tenant_id = Ecto.UUID.generate()
    slug = attrs[:slug] || generate_slug(attrs[:name])
    
    with {:ok, couchdb_db} <- create_couchdb_database(slug),
         {:ok, postgres_schema} <- create_postgres_schema(slug),
         {:ok, s3_buckets} <- create_s3_buckets(slug),
         :ok <- create_namespace(slug) do
      
      tenant = %Tenant{
        id: tenant_id,
        name: attrs[:name],
        slug: slug,
        email: attrs[:email],
        plan: attrs[:plan] || "free",
        couchdb_database: couchdb_db,
        postgres_schema: postgres_schema,
        s3_buckets: s3_buckets,
        namespace: slug,
        created_at: DateTime.utc_now(),
        status: :active
      }
      
      {:ok, tenant}
    else
      error -> error
    end
  end
  
  defp create_couchdb_database(slug) do
    database_name = "przma_#{slug}"
    
    # Create database via CouchDB HTTP API
    case HTTPoison.put(
      "#{couchdb_url()}/#{database_name}",
      "",
      [{"Content-Type", "application/json"}],
      [hackney: [basic_auth: couchdb_credentials()]]
    ) do
      {:ok, %{status_code: 201}} ->
        # Set up partition key
        setup_partitioned_database(database_name)
        {:ok, database_name}
      
      {:ok, %{status_code: 412}} ->
        {:error, :database_exists}
      
      error ->
        {:error, error}
    end
  end
  
  defp create_postgres_schema(slug) do
    schema_name = "tenant_#{slug}"
    
    # Create schema via Ecto
    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      "CREATE SCHEMA IF NOT EXISTS #{schema_name}",
      []
    ) do
      {:ok, _} ->
        # Create tables in schema
        create_tenant_tables(schema_name)
        {:ok, schema_name}
      
      error ->
        {:error, error}
    end
  end
  
  defp create_s3_buckets(slug) do
    buckets = Enum.reduce(@bucket_types, %{}, fn type, acc ->
      bucket_name = "przma-#{slug}-#{type}"
      
      case create_s3_bucket(bucket_name) do
        {:ok, bucket} ->
          Map.put(acc, type, bucket)
        
        {:error, _} ->
          acc
      end
    end)
    
    {:ok, buckets}
  end
  
  defp create_s3_bucket(bucket_name) do
    # Use ExAws to create bucket
    case ExAws.S3.put_bucket(bucket_name, Application.get_env(:przma, :aws_region))
    |> ExAws.request() do
      {:ok, _} -> {:ok, bucket_name}
      error -> {:error, error}
    end
  end
  
  defp create_namespace(slug) do
    # Create Kubernetes namespace if using K8s
    # Or directory structure for local development
    namespace_path = Path.join([Application.get_env(:przma, :data_root), slug])
    File.mkdir_p(namespace_path)
    :ok
  end
  
  defp setup_partitioned_database(database_name) do
    # Configure CouchDB partitioning for multi-tenancy
    design_doc = %{
      "_id" => "_design/tenant",
      "options" => %{
        "partitioned" => true
      }
    }
    
    HTTPoison.put(
      "#{couchdb_url()}/#{database_name}/_design/tenant",
      Jason.encode!(design_doc),
      [{"Content-Type", "application/json"}],
      [hackney: [basic_auth: couchdb_credentials()]]
    )
  end
  
  defp create_tenant_tables(schema_name) do
    # Create necessary tables in tenant schema
    Ecto.Adapters.SQL.query(Przma.Repo, """
      CREATE TABLE IF NOT EXISTS #{schema_name}.activities (
        id UUID PRIMARY KEY,
        actor TEXT NOT NULL,
        verb TEXT NOT NULL,
        object JSONB NOT NULL,
        target JSONB,
        published TIMESTAMP NOT NULL,
        metadata JSONB,
        embedding vector(1536)
      )
    """, [])
    
    # Create indexes
    Ecto.Adapters.SQL.query(Przma.Repo, """
      CREATE INDEX IF NOT EXISTS idx_#{schema_name}_activities_actor 
      ON #{schema_name}.activities(actor)
    """, [])
    
    Ecto.Adapters.SQL.query(Przma.Repo, """
      CREATE INDEX IF NOT EXISTS idx_#{schema_name}_activities_verb 
      ON #{schema_name}.activities(verb)
    """, [])
    
    Ecto.Adapters.SQL.query(Przma.Repo, """
      CREATE INDEX IF NOT EXISTS idx_#{schema_name}_activities_embedding 
      ON #{schema_name}.activities USING ivfflat (embedding vector_cosine_ops)
    """, [])
  end
  
  defp cleanup_tenant_resources(tenant) do
    with :ok <- delete_couchdb_database(tenant.couchdb_database),
         :ok <- delete_postgres_schema(tenant.postgres_schema),
         :ok <- delete_s3_buckets(tenant.s3_buckets),
         :ok <- delete_namespace(tenant.namespace) do
      :ok
    else
      error -> error
    end
  end
  
  defp delete_couchdb_database(database_name) do
    case HTTPoison.delete(
      "#{couchdb_url()}/#{database_name}",
      [],
      [hackney: [basic_auth: couchdb_credentials()]]
    ) do
      {:ok, %{status_code: 200}} -> :ok
      error -> {:error, error}
    end
  end
  
  defp delete_postgres_schema(schema_name) do
    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      "DROP SCHEMA IF EXISTS #{schema_name} CASCADE",
      []
    ) do
      {:ok, _} -> :ok
      error -> {:error, error}
    end
  end
  
  defp delete_s3_buckets(buckets) do
    Enum.each(buckets, fn {_type, bucket_name} ->
      # Empty bucket first
      ExAws.S3.delete_all_objects(bucket_name, "")
      |> ExAws.request()
      
      # Delete bucket
      ExAws.S3.delete_bucket(bucket_name)
      |> ExAws.request()
    end)
    
    :ok
  end
  
  defp delete_namespace(slug) do
    namespace_path = Path.join([Application.get_env(:przma, :data_root), slug])
    File.rm_rf(namespace_path)
    :ok
  end
  
  defp apply_filters(tenants, filters) do
    Enum.filter(tenants, fn tenant ->
      Enum.all?(filters, fn {key, value} ->
        Map.get(tenant, key) == value
      end)
    end)
  end
  
  defp generate_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
  
  defp couchdb_url do
    Application.get_env(:przma, :couchdb_url, "http://localhost:5984")
  end
  
  defp couchdb_credentials do
    {
      Application.get_env(:przma, :couchdb_user, "admin"),
      Application.get_env(:przma, :couchdb_password, "password")
    }
  end
end
