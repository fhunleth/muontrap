defmodule MuonTrap.MixProject do
  use Mix.Project

  def project do
    [
      app: :muontrap,
      version: "0.4.3",
      elixir: "~> 1.6",
      description: "Keep your ports contained",
      source_url: "https://github.com/fhunleth/muontrap",
      docs: [extras: ["README.md"], main: "readme"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      build_embedded: true,
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      dialyzer: [
        flags: [:unmatched_returns, :error_handling, :race_conditions, :underspecs]
      ],
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps() do
    [
      {:elixir_make, "~> 0.5", runtime: false},
      {:ex_doc, "~> 0.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package() do
    [
      files: [
        "lib",
        "src/*.[ch]",
        "src/Makefile",
        "Makefile",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/fhunleth/muontrap"}
    ]
  end
end
