defmodule Przma.ActivityStreams.VerbMapping do
  @moduledoc """
  Maps ActivityStreams verbs to PRESERVE and 7P frameworks.
  """

  @verb_mappings %{
    # Presence & Awareness
    "attend" => %{preserve: ["presence"], seven_p: ["places", "people"]},
    "arrive" => %{preserve: ["presence"], seven_p: ["places"]},
    "leave" => %{preserve: ["presence"], seven_p: ["places"]},
    "experience" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    "observe" => %{preserve: ["presence"], seven_p: ["perspectives"]},

    # Relationships
    "connect" => %{preserve: ["relationships"], seven_p: ["people"]},
    "meet" => %{preserve: ["relationships"], seven_p: ["people"]},
    "call" => %{preserve: ["relationships"], seven_p: ["people"]},
    "message" => %{preserve: ["relationships"], seven_p: ["people"]},
    "collaborate" => %{preserve: ["relationships"], seven_p: ["people", "progress"]},

    # Learning & Enablement
    "learn" => %{preserve: ["enablement"], seven_p: ["pursuits", "progress"]},
    "teach" => %{preserve: ["enablement", "relationships"], seven_p: ["people", "pursuits"]},
    "study" => %{preserve: ["enablement"], seven_p: ["pursuits"]},
    "practice" => %{preserve: ["enablement", "execution"], seven_p: ["pursuits", "progress"]},
    "master" => %{preserve: ["enablement", "excellence"], seven_p: ["pursuits", "progress"]},

    # Creation & Stories
    "create" => %{preserve: ["stories", "value_creation"], seven_p: ["portfolio", "progress"]},
    "write" => %{preserve: ["stories"], seven_p: ["portfolio"]},
    "design" => %{preserve: ["stories", "value_creation"], seven_p: ["portfolio"]},
    "build" => %{preserve: ["execution", "value_creation"], seven_p: ["portfolio", "progress"]},
    "publish" => %{preserve: ["stories"], seven_p: ["portfolio"]},

    # Execution & Progress
    "complete" => %{preserve: ["execution"], seven_p: ["progress"]},
    "achieve" => %{preserve: ["execution", "excellence"], seven_p: ["progress"]},
    "accomplish" => %{preserve: ["execution"], seven_p: ["progress"]},
    "finish" => %{preserve: ["execution"], seven_p: ["progress"]},
    "deliver" => %{preserve: ["execution", "value_creation"], seven_p: ["progress", "portfolio"]},

    # Resources & Value
    "acquire" => %{preserve: ["resources"], seven_p: ["portfolio"]},
    "invest" => %{preserve: ["resources", "value_creation"], seven_p: ["portfolio", "progress"]},
    "save" => %{preserve: ["resources"], seven_p: ["portfolio"]},
    "earn" => %{preserve: ["resources", "value_creation"], seven_p: ["portfolio", "progress"]},
    "purchase" => %{preserve: ["resources"], seven_p: ["portfolio"]},

    # Excellence & Growth
    "improve" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "optimize" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "excel" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "refine" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "perfect" => %{preserve: ["excellence"], seven_p: ["progress"]},

    # Reflection & Purpose
    "reflect" => %{preserve: ["presence", "stories"], seven_p: ["perspectives", "purpose"]},
    "journal" => %{preserve: ["stories"], seven_p: ["perspectives"]},
    "meditate" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    "contemplate" => %{preserve: ["presence"], seven_p: ["perspectives", "purpose"]},
    "envision" => %{preserve: ["stories"], seven_p: ["purpose"]},

    # Sharing & Connection
    "share" => %{preserve: ["relationships", "value_creation"], seven_p: ["people", "portfolio"]},
    "contribute" => %{preserve: ["value_creation", "relationships"], seven_p: ["people", "progress"]},
    "give" => %{preserve: ["value_creation", "relationships"], seven_p: ["people"]},
    "help" => %{preserve: ["relationships", "enablement"], seven_p: ["people"]},
    "support" => %{preserve: ["relationships", "enablement"], seven_p: ["people"]},

    # Consumption & Experience
    "read" => %{preserve: ["enablement"], seven_p: ["pursuits"]},
    "watch" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "listen" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "consume" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "enjoy" => %{preserve: ["presence"], seven_p: ["perspectives"]},

    # Planning & Strategy
    "plan" => %{preserve: ["stories", "execution"], seven_p: ["progress", "purpose"]},
    "organize" => %{preserve: ["execution"], seven_p: ["progress"]},
    "strategize" => %{preserve: ["stories", "execution"], seven_p: ["purpose", "progress"]},
    "prepare" => %{preserve: ["execution"], seven_p: ["progress"]},
    "schedule" => %{preserve: ["execution"], seven_p: ["progress"]},

    # Health & Wellness
    "exercise" => %{preserve: ["presence", "execution"], seven_p: ["pursuits", "progress"]},
    "rest" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    "heal" => %{preserve: ["presence", "excellence"], seven_p: ["progress"]},
    "nourish" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "relax" => %{preserve: ["presence"], seven_p: ["perspectives"]}
  }

  def verb_to_preserve(verb) do
    case Map.get(@verb_mappings, verb) do
      %{preserve: categories} -> categories
      nil -> []
    end
  end

  def verb_to_seven_p(verb) do
    case Map.get(@verb_mappings, verb) do
      %{seven_p: categories} -> categories
      nil -> []
    end
  end

  def all_verbs do
    Map.keys(@verb_mappings)
  end

  def get_mapping(verb) do
    Map.get(@verb_mappings, verb)
  end
end
