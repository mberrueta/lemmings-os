defmodule LemmingsOs.Config.RuntimeDocumentsConfigTest do
  use ExUnit.Case, async: false

  @runtime_config_path Path.expand("../../../config/runtime.exs", __DIR__)

  describe "documents runtime env contract" do
    test "uses defaults when document env vars are unset" do
      with_env(
        %{
          "LEMMINGS_GOTENBERG_URL" => nil,
          "LEMMINGS_DOCUMENTS_PDF_TIMEOUT_MS" => nil,
          "LEMMINGS_DOCUMENTS_PDF_CONNECT_TIMEOUT_MS" => nil,
          "LEMMINGS_DOCUMENTS_PDF_RETRIES" => nil,
          "LEMMINGS_DOCUMENTS_MAX_SOURCE_BYTES" => nil,
          "LEMMINGS_DOCUMENTS_MAX_PDF_BYTES" => nil,
          "LEMMINGS_DOCUMENTS_MAX_FALLBACK_BYTES" => nil,
          "LEMMINGS_DOCUMENTS_DEFAULT_HEADER_PATH" => nil,
          "LEMMINGS_DOCUMENTS_DEFAULT_FOOTER_PATH" => nil,
          "LEMMINGS_DOCUMENTS_DEFAULT_CSS_PATH" => nil
        },
        fn ->
          with_documents_app_env(nil, fn ->
            assert runtime_documents_config(:dev) == [
                     gotenberg_url: "http://gotenberg:3000",
                     pdf_timeout_ms: 30_000,
                     pdf_connect_timeout_ms: 5_000,
                     pdf_retries: 1,
                     max_source_bytes: 10 * 1024 * 1024,
                     max_pdf_bytes: 50 * 1024 * 1024,
                     max_fallback_bytes: 1 * 1024 * 1024,
                     default_header_path: nil,
                     default_footer_path: nil,
                     default_css_path: nil
                   ]
          end)
        end
      )
    end

    test "uses env overrides for documents config values" do
      with_env(
        %{
          "LEMMINGS_GOTENBERG_URL" => "http://127.0.0.1:8123",
          "LEMMINGS_DOCUMENTS_PDF_TIMEOUT_MS" => "1234",
          "LEMMINGS_DOCUMENTS_PDF_CONNECT_TIMEOUT_MS" => "2345",
          "LEMMINGS_DOCUMENTS_PDF_RETRIES" => "3",
          "LEMMINGS_DOCUMENTS_MAX_SOURCE_BYTES" => "3456",
          "LEMMINGS_DOCUMENTS_MAX_PDF_BYTES" => "4567",
          "LEMMINGS_DOCUMENTS_MAX_FALLBACK_BYTES" => "5678",
          "LEMMINGS_DOCUMENTS_DEFAULT_HEADER_PATH" => "priv/documents/header.html",
          "LEMMINGS_DOCUMENTS_DEFAULT_FOOTER_PATH" => "priv/documents/footer.html",
          "LEMMINGS_DOCUMENTS_DEFAULT_CSS_PATH" => "priv/documents/default.css"
        },
        fn ->
          with_documents_app_env(nil, fn ->
            assert runtime_documents_config(:dev) == [
                     gotenberg_url: "http://127.0.0.1:8123",
                     pdf_timeout_ms: "1234",
                     pdf_connect_timeout_ms: "2345",
                     pdf_retries: "3",
                     max_source_bytes: "3456",
                     max_pdf_bytes: "4567",
                     max_fallback_bytes: "5678",
                     default_header_path: "priv/documents/header.html",
                     default_footer_path: "priv/documents/footer.html",
                     default_css_path: "priv/documents/default.css"
                   ]
          end)
        end
      )
    end

    test "empty fallback env vars are treated as unset" do
      with_env(
        %{
          "LEMMINGS_DOCUMENTS_DEFAULT_HEADER_PATH" => "",
          "LEMMINGS_DOCUMENTS_DEFAULT_FOOTER_PATH" => "",
          "LEMMINGS_DOCUMENTS_DEFAULT_CSS_PATH" => ""
        },
        fn ->
          with_documents_app_env(nil, fn ->
            documents = runtime_documents_config(:dev)
            assert Keyword.get(documents, :default_header_path) == nil
            assert Keyword.get(documents, :default_footer_path) == nil
            assert Keyword.get(documents, :default_css_path) == nil
          end)
        end
      )
    end

    test "keeps invalid numeric env values for adapter-time validation" do
      with_env(
        %{"LEMMINGS_DOCUMENTS_PDF_TIMEOUT_MS" => "30s"},
        fn ->
          with_documents_app_env(nil, fn ->
            documents = runtime_documents_config(:dev)
            assert Keyword.get(documents, :pdf_timeout_ms) == "30s"
          end)
        end
      )
    end
  end

  defp runtime_documents_config(env) do
    {config, _imports} = Config.Reader.read_imports!(@runtime_config_path, env: env)
    lemmings_os_config = Keyword.get(config, :lemmings_os, [])
    Keyword.get(lemmings_os_config, :documents, [])
  end

  defp with_documents_app_env(value, fun) do
    previous = Application.get_env(:lemmings_os, :documents, :__missing__)

    try do
      if is_nil(value) do
        Application.delete_env(:lemmings_os, :documents)
      else
        Application.put_env(:lemmings_os, :documents, value)
      end

      fun.()
    after
      case previous do
        :__missing__ -> Application.delete_env(:lemmings_os, :documents)
        config -> Application.put_env(:lemmings_os, :documents, config)
      end
    end
  end

  defp with_env(changes, fun) do
    previous = Map.new(changes, fn {key, _value} -> {key, System.get_env(key)} end)

    try do
      Enum.each(changes, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
