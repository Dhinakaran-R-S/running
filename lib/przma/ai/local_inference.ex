defmodule Przma.AI.LocalInference do
  @moduledoc """
  Manages local AI model inference using Ollama or similar.
  All inference happens on-device, never sending data externally.

  Supported models:
  - llama3.2:3b - Fast intent/classification
  - llama3.1:8b - Complex reasoning
  - nomic-embed-text - Embeddings
  - llava:13b - Vision/image analysis
  """

  use GenServer
  require Logger

  @ollama_url "http://localhost:11434"
  @cache_ttl 3600  # 1 hour in seconds

  defmodule InferenceRequest do
    defstruct [
      :task_type,
      :prompt,
      :model,
      :parameters,
      :context
    ]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Infer intent from text using local LLM.
  """
  def infer_intent(text, context \\ %{}) do
    request = %InferenceRequest{
      task_type: :intent,
      prompt: text,
      model: "llama3.2:3b",
      context: context
    }

    GenServer.call(__MODULE__, {:infer, request}, 30_000)
  end

  @doc """
  Detect emotions from text.
  """
  def detect_emotions(text, context \\ %{}) do
    request = %InferenceRequest{
      task_type: :emotion,
      prompt: text,
      model: "llama3.2:3b",
      context: context
    }

    GenServer.call(__MODULE__, {:infer, request}, 30_000)
  end

  @doc """
  Extract entities and concepts from text.
  """
  def extract_entities(text, context \\ %{}) do
    request = %InferenceRequest{
      task_type: :entities,
      prompt: text,
      model: "llama3.1:8b",
      context: context
    }

    GenServer.call(__MODULE__, {:infer, request}, 30_000)
  end

  @doc """
  Generate embeddings for semantic search.
  """
  def generate_embeddings(text) do
    request = %InferenceRequest{
      task_type: :embedding,
      prompt: text,
      model: "nomic-embed-text"
    }

    GenServer.call(__MODULE__, {:infer, request}, 30_000)
  end

  @doc """
  Analyze an image with vision model.
  """
  def analyze_image(image_data, prompt) do
    request = %InferenceRequest{
      task_type: :vision,
      prompt: prompt,
      model: "llava:13b",
      parameters: %{image: image_data}
    }

    GenServer.call(__MODULE__, {:infer, request}, 60_000)
  end

  @doc """
  Check if models are loaded and ready.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  # Server Callbacks

  def init(_opts) do
    # Preload models into memory for faster inference
    models = [
      "llama3.2:3b",
      "llama3.1:8b",
      "nomic-embed-text",
      "llava:13b"
    ]

    Logger.info("Initializing LocalInference with models: #{inspect(models)}")

    # Verify Ollama is running
    case HTTPoison.get("#{@ollama_url}/api/tags") do
      {:ok, %{status_code: 200}} ->
        Logger.info("Ollama is running")

        # Ensure models are loaded
        Enum.each(models, &ensure_model_loaded/1)

        state = %{
          loaded_models: MapSet.new(models),
          inference_cache: %{},
          metrics: %{
            total_inferences: 0,
            cache_hits: 0,
            cache_misses: 0
          }
        }

        {:ok, state}

      error ->
        Logger.error("Failed to connect to Ollama: #{inspect(error)}")
        {:stop, :ollama_not_available}
    end
  end

  def handle_call({:infer, request}, _from, state) do
    # Check cache first
    cache_key = generate_cache_key(request)

    case get_from_cache(state.inference_cache, cache_key) do
      {:ok, cached_result} ->
        new_metrics = %{state.metrics | cache_hits: state.metrics.cache_hits + 1}
        {:reply, {:ok, cached_result}, %{state | metrics: new_metrics}}

      :miss ->
        # Run inference
        case run_local_inference(request) do
          {:ok, result} ->
            # Update cache
            new_cache = put_in_cache(state.inference_cache, cache_key, result)

            new_metrics = %{
              state.metrics |
              cache_misses: state.metrics.cache_misses + 1,
              total_inferences: state.metrics.total_inferences + 1
            }

            new_state = %{
              state |
              inference_cache: new_cache,
              metrics: new_metrics
            }

            {:reply, {:ok, result}, new_state}

          {:error, reason} ->
            Logger.error("Inference failed: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:health_check, _from, state) do
    health = %{
      status: :healthy,
      loaded_models: MapSet.to_list(state.loaded_models),
      cache_size: map_size(state.inference_cache),
      metrics: state.metrics
    }

    {:reply, health, state}
  end

  # Private Functions

  defp ensure_model_loaded(model_name) do
    Logger.info("Ensuring model is loaded: #{model_name}")

    # Pull model if not already present
    case HTTPoison.post(
      "#{@ollama_url}/api/pull",
      Jason.encode!(%{name: model_name}),
      [{"Content-Type", "application/json"}]
    ) do
      {:ok, %{status_code: 200}} ->
        Logger.info("Model #{model_name} is ready")
        :ok

      error ->
        Logger.warning("Failed to ensure model #{model_name}: #{inspect(error)}")
        :ok
    end
  end

  defp run_local_inference(%InferenceRequest{task_type: :intent} = request) do
    prompt = build_intent_prompt(request.prompt, request.context)
    generate_completion(request.model, prompt)
  end

  defp run_local_inference(%InferenceRequest{task_type: :emotion} = request) do
    prompt = build_emotion_prompt(request.prompt)
    generate_completion(request.model, prompt)
  end

  defp run_local_inference(%InferenceRequest{task_type: :entities} = request) do
    prompt = build_entity_prompt(request.prompt)
    generate_completion(request.model, prompt)
  end

  defp run_local_inference(%InferenceRequest{task_type: :embedding} = request) do
    generate_embedding(request.model, request.prompt)
  end

  defp run_local_inference(%InferenceRequest{task_type: :vision} = request) do
    generate_vision_completion(
      request.model,
      request.prompt,
      request.parameters.image
    )
  end

  defp generate_completion(model, prompt) do
    payload = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: 0.7,
        top_p: 0.9,
        top_k: 40
      }
    }

    case HTTPoison.post(
      "#{@ollama_url}/api/generate",
      Jason.encode!(payload),
      [{"Content-Type", "application/json"}],
      [recv_timeout: 30_000]
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        {:ok, response["response"]}

      error ->
        {:error, error}
    end
  end

  defp generate_embedding(model, text) do
    payload = %{
      model: model,
      prompt: text
    }

    case HTTPoison.post(
      "#{@ollama_url}/api/embeddings",
      Jason.encode!(payload),
      [{"Content-Type", "application/json"}],
      [recv_timeout: 30_000]
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        {:ok, response["embedding"]}

      error ->
        {:error, error}
    end
  end

  defp generate_vision_completion(model, prompt, image_data) do
    payload = %{
      model: model,
      prompt: prompt,
      images: [Base.encode64(image_data)],
      stream: false
    }

    case HTTPoison.post(
      "#{@ollama_url}/api/generate",
      Jason.encode!(payload),
      [{"Content-Type", "application/json"}],
      [recv_timeout: 60_000]
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        {:ok, response["response"]}

      error ->
        {:error, error}
    end
  end

  defp build_intent_prompt(text, context) do
    """
    Analyze the following text and determine the primary intent.

    Text: "#{text}"

    #{if map_size(context) > 0, do: "Context: #{Jason.encode!(context)}", else: ""}

    Respond with ONLY a JSON object in this format:
    {
      "primary_intent": "one of: inform, question, request, express_emotion, reflect, plan, report",
      "confidence": 0.0 to 1.0,
      "secondary_intents": ["list", "of", "secondary", "intents"]
    }

    DO NOT include any explanation, only the JSON object.
    """
  end

  defp build_emotion_prompt(text) do
    """
    Analyze the emotional content of the following text.

    Text: "#{text}"

    Respond with ONLY a JSON object in this format:
    {
      "primary_emotion": "joy, sadness, anger, fear, surprise, disgust, neutral",
      "intensity": 0.0 to 1.0,
      "secondary_emotions": ["list", "of", "emotions"],
      "emotional_tone": "positive, negative, or neutral"
    }

    DO NOT include any explanation, only the JSON object.
    """
  end

  defp build_entity_prompt(text) do
    """
    Extract key entities, concepts, and topics from the following text.

    Text: "#{text}"

    Respond with ONLY a JSON object in this format:
    {
      "entities": [
        {"text": "entity name", "type": "person, place, organization, thing", "relevance": 0.0-1.0}
      ],
      "concepts": ["abstract concept 1", "abstract concept 2"],
      "topics": ["topic 1", "topic 2"],
      "keywords": ["keyword1", "keyword2"]
    }

    DO NOT include any explanation, only the JSON object.
    """
  end

  defp generate_cache_key(request) do
    content = "#{request.task_type}:#{request.model}:#{request.prompt}"
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp get_from_cache(cache, key) do
    case Map.get(cache, key) do
      nil ->
        :miss

      {result, timestamp} ->
        if System.system_time(:second) - timestamp < @cache_ttl do
          {:ok, result}
        else
          :miss
        end
    end
  end

  defp put_in_cache(cache, key, result) do
    timestamp = System.system_time(:second)
    Map.put(cache, key, {result, timestamp})
  end
end
