defmodule SnaWeb.AuthController do
  use SnaWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def email(conn, %{"email" => email}) do
    case SnaWeb.Token.generate_bearer(%{"email" => email}) do
      {:ok, token, _claims} ->
        render(conn, "email.html", email: email, token: token)
      {:error, reason} ->
        Logger.error("Internal error, could not verify token: #{inspect(reason)}")
        msg = SnaWeb.Token.error_message("Internal error, could not generate token", reason)
        conn
          |> put_flash(:error, msg)
          |> redirect(to: "/auth")
          |> halt()
    end
  end

  def email(conn, params = %{"token" => token}) do
    case [SnaWeb.Token.validate_bearer(token), params] do
      [{:ok, %{"email" => email}}, %{"login" => login}] ->
        inserted = Sna.Repo.User.insert(%{
          email: email,
          login: login,
          admin: false,
        })
        case inserted do
          {:ok, record} ->
            conn
              |> put_session("auth_token", token)
              |> put_session("auth_user_id", record.id)
              |> redirect(to: "/")
              |> halt()
          {:error, %{errors: [ email: { _, [ constraint: :unique, constraint_name: _ ] } ]}} ->
            conn
              |> put_flash(:error, "You already registered")
              |> redirect(to: "/")
              |> halt()
          {:error, errors} ->
            errors = Ecto.Changeset.traverse_errors(errors, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)
            conn
              |> render("first-login.html", token: token, email: email, errors: errors)
        end
      [{:ok, %{"email" => email}}, _] ->
        case Sna.Repo.User.get_by_email(email) do
          nil ->
            conn
              |> render("first-login.html", token: token, email: email)
          %{ id: user_id } ->
            conn
              |> put_session("auth_token", token)
              |> put_session("auth_user_id", user_id)
              |> redirect(to: "/")
              |> halt()
        end
      [{:error, reason}, _] ->
        Logger.error("Could not verify token: #{inspect(reason)}")
        msg = SnaWeb.Token.error_message("Could not verify token", reason)
        conn
          |> put_flash(:error, msg)
          |> redirect(to: "/auth")
          |> halt()
      [_, _] ->
        conn
          |> put_flash(:error, "No valid claims in this token")
          |> redirect(to: "/auth")
          |> halt()
    end
  end

  def logout(conn, _params) do
    conn
      |> delete_session("auth_token")
      |> delete_session("auth_user_id")
      |> put_flash(:info, "You are logged out")
      |> redirect(to: "/")
      |> halt()
  end
end
