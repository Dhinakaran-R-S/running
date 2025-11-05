defmodule PrzmaWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use PrzmaWeb, :controller` and
  `use PrzmaWeb, :live_view`.
  """
  use PrzmaWeb, :html

  embed_templates "layouts/*"
end
