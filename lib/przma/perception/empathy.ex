defmodule Przma.Perception.Empathy do
  @behaviour Przma.Perception.EnrichmentBehavior
  def enrich_activity(_activity, _member), do: %{}
end
