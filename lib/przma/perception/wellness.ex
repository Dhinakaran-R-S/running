defmodule Przma.Perception.Wellness do
  @behaviour Przma.Perception.EnrichmentBehavior
  def enrich_activity(_activity, _member), do: %{}
end
