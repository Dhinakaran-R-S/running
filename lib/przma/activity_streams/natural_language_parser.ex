defmodule Przma.ActivityStreams.NaturalLanguageParser do
  @moduledoc """
  Parses natural language into structured ActivityStreams.
  """

  @verb_patterns %{
    ~r/attended|went to|joined/i => "attend",
    ~r/learned|studied|took a course/i => "learn",
    ~r/created|made|built/i => "create",
    ~r/completed|finished|accomplished/i => "complete",
    ~r/met|connected with|talked to/i => "meet",
    ~r/read|reading/i => "read",
    ~r/watched|viewing/i => "watch",
    ~r/exercised|worked out/i => "exercise",
    ~r/reflected|journaled|thought about/i => "reflect",
    ~r/shared|posted|published/i => "share"
  }

  def parse(text) do
    verb = extract_verb(text)
    object = extract_object(text, verb)

    {:ok, %{
      verb: verb,
      object: object
    }}
  end

  defp extract_verb(text) do
    Enum.find_value(@verb_patterns, "experience", fn {pattern, verb} ->
      if String.match?(text, pattern), do: verb
    end)
  end

  defp extract_object(text, _verb) do
    # Simple extraction - in production, use NLP library
    # Extract the main noun phrase after the verb
    words = String.split(text, " ")
    object_words = Enum.drop(words, 1)

    %{
      type: "Thing",
      name: Enum.join(object_words, " ")
    }
  end
end
