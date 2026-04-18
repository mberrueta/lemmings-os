defmodule LemmingsOs.ModelRuntime.Providers.OllamaTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias LemmingsOs.ModelRuntime.Providers.Ollama

  setup do
    bypass = Bypass.open()
    [bypass: bypass]
  end

  test "S01: chat/2 posts a json chat request and extracts usage", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["model"] == "llama3.2"
      assert payload["format"] == "json"
      assert [%{"role" => "system"}, %{"role" => "user"}] = payload["messages"]

      response_body =
        Jason.encode!(%{
          "model" => "llama3.2",
          "message" => %{"content" => ~s({"action":"reply","reply":"hello"})},
          "prompt_eval_count" => 10,
          "eval_count" => 2,
          "prompt_eval_duration" => 100,
          "eval_duration" => 200,
          "total_duration" => 300
        })

      Plug.Conn.resp(conn, 200, response_body)
    end)

    assert {:ok, response} =
             Ollama.chat(
               %{
                 model: "llama3.2",
                 messages: [
                   %{role: "system", content: "Be concise."},
                   %{role: "user", content: "Hello"}
                 ],
                 format: "json"
               },
               base_url: "http://127.0.0.1:#{bypass.port}",
               timeout: 1_000
             )

    assert response.content == ~s({"action":"reply","reply":"hello"})
    assert response.provider == "ollama"
    assert response.model == "llama3.2"
    assert response.input_tokens == 10
    assert response.output_tokens == 2
    assert response.total_tokens == 12

    assert response.usage == %{
             prompt_eval_count: 10,
             eval_count: 2,
             total_duration: 300,
             prompt_eval_duration: 100,
             eval_duration: 200
           }

    assert response.raw["message"]["content"] == ~s({"action":"reply","reply":"hello"})
  end

  test "S02: chat/2 returns enriched provider error for non-success responses", %{
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      Plug.Conn.resp(conn, 500, ~s({"error":"boom"}))
    end)

    assert capture_log(fn ->
             assert {:error,
                     {:provider_http_error, %{provider: "ollama", status: 500, detail: "boom"}}} =
                      Ollama.chat(
                        %{
                          model: "llama3.2",
                          messages: [%{role: "user", content: "Hello"}],
                          format: "json"
                        },
                        base_url: "http://127.0.0.1:#{bypass.port}",
                        timeout: 1_000
                      )
           end) =~ "ollama provider returned a non-success response"
  end

  test "S03: chat/2 returns a provider network error when the server is unavailable" do
    assert capture_log(fn ->
             assert {:error, {:provider_network_error, %{provider: "ollama", reason: reason}}} =
                      Ollama.chat(
                        %{
                          model: "llama3.2",
                          messages: [%{role: "user", content: "Hello"}],
                          format: "json"
                        },
                        base_url: "http://127.0.0.1:1",
                        timeout: 1_000
                      )

             assert is_binary(reason)
           end) =~ "ollama provider request failed"
  end

  test "S04: chat/2 does not follow redirects automatically", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://127.0.0.1:1/redirected")
      |> Plug.Conn.resp(302, "")
    end)

    assert capture_log(fn ->
             assert {:error,
                     {:provider_http_error, %{provider: "ollama", status: 302, detail: ""}}} =
                      Ollama.chat(
                        %{
                          model: "llama3.2",
                          messages: [%{role: "user", content: "Hello"}],
                          format: "json"
                        },
                        base_url: "http://127.0.0.1:#{bypass.port}",
                        timeout: 1_000
                      )
           end) =~ "ollama provider returned a non-success response"
  end
end
