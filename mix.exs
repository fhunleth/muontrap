defmodule MuonTrap.MixProject do
  use Mix.Project

  @version "1.5.0"
  @source_url "https://github.com/fhunleth/muontrap"

  def project do
    [
      app: :muontrap,
      version: @version,
      elixir: "~> 1.11",
      description: "Keep your ports contained",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      dialyzer: [
        flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs]
      ],
      package: package(),
      preferred_cli_env: %{
        docs: :docs,
        "hex.publish": :docs,
        "hex.build": :docs
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [extra_applications: [:logger]]
  end

  defp deps() do
    [
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.19", only: :docs, runtime: false},
      {:dialyxir, "~> 1.2", only: :dev, runtime: false},
      {:credo, "~> 1.5", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp package() do
    [
      files: [
        "CHANGELOG.md",
        "README.md",
        "lib",
        "c_src/*.[ch]",
        "c_src/Makefile",
        "Makefile",
        "mix.exs",
        "LICENSES/*"
      ],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
