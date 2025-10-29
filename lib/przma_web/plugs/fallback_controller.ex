defmodule PrzmaWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  """

  use Phoenix.Controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("404.json")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("401.json")
  end

  def call(conn, {:error, changeset = %Ecto.Changeset{}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("error.json", changeset: changeset)
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:bad_request)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("error.json", error: reason)
  end
end
