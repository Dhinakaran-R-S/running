defmodule PrzmaWeb.DashboardLive do
  use PrzmaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :message, "Welcome to your dashboard!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100">
      <!-- Header -->
      <div class="bg-white shadow">
        <div class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <h1 class="text-3xl font-bold text-gray-900"><%= @message %></h1>
        </div>
      </div>

      <!-- Main Content -->
      <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <div class="px-4 py-6 sm:px-0">
          <div class="border-4 border-dashed border-gray-200 rounded-lg h-96 p-4">
            <p class="text-gray-500">Dashboard content goes here</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
