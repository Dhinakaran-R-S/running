defmodule Przma.Perception.EnrichmentBehavior do
  @moduledoc """
  Behavior for perception enrichment modules.
  All enrichment modules should implement this behavior.
  """

  @callback enrich_activity(activity :: map(), member :: map()) :: map()
end
