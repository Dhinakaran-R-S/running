defmodule PrzmaWeb.AuthController do
  @moduledoc """
  Authentication controller handling login, logout, token refresh, and registration.
  """
  
  use PrzmaWeb, :controller
  
  alias Przma.Auth
  alias Przma.AuditLog
  alias PrzmaWeb.ErrorView
  
  action_fallback PrzmaWeb.FallbackController
  
  @doc """
  User login with username/email and password.
  """
  def login(conn, %{"username" => username, "password" => password}) do
    context = %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn)
    }
    
    case Auth.authenticate(username, password) do
      {:ok, user, tokens} ->
        # Log successful login
        AuditLog.log_action(user, :login, :user, user.id, context)
        
        conn
        |> put_status(:ok)
        |> render("tokens.json", tokens: tokens, user: user)
      
      {:error, :invalid_credentials} ->
        # Log failed login attempt
        AuditLog.log_security_event(%{username: username}, :failed_login, 
          Map.merge(context, %{status: :failure}))
        
        conn
        |> put_status(:unauthorized)
        |> render(ErrorView, "error.json", error: "Invalid credentials")
    end
  end
  
  @doc """
  User registration.
  """
  def register(conn, %{"user" => user_params}) do
    context = %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn)
    }
    
    case Auth.register(user_params) do
      {:ok, user} ->
        # Log registration
        AuditLog.log_action(user, :register, :user, user.id, context)
        
        # Auto-login after registration
        {:ok, _user, tokens} = Auth.authenticate(user.username, user_params["password"])
        
        conn
        |> put_status(:created)
        |> render("tokens.json", tokens: tokens, user: user)
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Refresh access token using refresh token.
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Auth.refresh_token(refresh_token) do
      {:ok, tokens} ->
        render(conn, "tokens.json", tokens: tokens)
      
      {:error, :refresh_token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> render(ErrorView, "error.json", error: "Refresh token expired")
      
      {:error, :invalid_refresh_token} ->
        conn
        |> put_status(:unauthorized)
        |> render(ErrorView, "error.json", error: "Invalid refresh token")
    end
  end
  
  @doc """
  Logout user by revoking session.
  """
  def logout(conn, _params) do
    token = get_bearer_token(conn)
    user = conn.assigns.current_user
    
    case Auth.logout(token) do
      :ok ->
        # Log logout
        AuditLog.log_action(user, :logout, :user, user.id, %{
          ip_address: get_client_ip(conn)
        })
        
        send_resp(conn, :no_content, "")
      
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(ErrorView, "error.json", error: reason)
    end
  end
  
  @doc """
  Request password reset.
  """
  def request_password_reset(conn, %{"email" => email}) do
    # Always return success to prevent email enumeration
    Auth.request_password_reset(email)
    
    json(conn, %{message: "If the email exists, a reset link will be sent"})
  end
  
  @doc """
  Reset password with token.
  """
  def reset_password(conn, %{"token" => token, "password" => new_password}) do
    case Auth.reset_password(token, new_password) do
      {:ok, user} ->
        # Log password reset
        AuditLog.log_action(user, :password_reset, :user, user.id, %{
          ip_address: get_client_ip(conn)
        })
        
        json(conn, %{message: "Password reset successful"})
      
      {:error, :invalid} ->
        conn
        |> put_status(:bad_request)
        |> render(ErrorView, "error.json", error: "Invalid or expired token")
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Change password (requires authentication).
  """
  def change_password(conn, %{"current_password" => current, "new_password" => new_pass}) do
    user = conn.assigns.current_user
    
    case Auth.change_password(user, current, new_pass) do
      {:ok, _user} ->
        # Log password change
        AuditLog.log_action(user, :password_change, :user, user.id, %{
          ip_address: get_client_ip(conn)
        })
        
        json(conn, %{message: "Password changed successfully"})
      
      {:error, :invalid_current_password} ->
        conn
        |> put_status(:unauthorized)
        |> render(ErrorView, "error.json", error: "Invalid current password")
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Get current user info.
  """
  def me(conn, _params) do
    user = conn.assigns.current_user
    render(conn, "user.json", user: user)
  end
  
  @doc """
  Revoke all sessions for current user.
  """
  def revoke_all_sessions(conn, _params) do
    user = conn.assigns.current_user
    
    Auth.revoke_all_tokens(user.id)
    
    # Log session revocation
    AuditLog.log_action(user, :revoke_all_sessions, :user, user.id, %{
      ip_address: get_client_ip(conn)
    })
    
    json(conn, %{message: "All sessions revoked"})
  end
  
  # Private Functions
  
  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
  
  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end
  
  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [agent | _] -> agent
      [] -> "unknown"
    end
  end
end
