defmodule Przma.Perception.Social do
  @behaviour Przma.Perception.EnrichmentBehavior
  def enrich_activity(_activity, _member), do: %{}
end
