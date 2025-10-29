defmodule Przma.Perception.Generativity do
  @behaviour Przma.Perception.EnrichmentBehavior
  def enrich_activity(_activity, _member), do: %{}
end
