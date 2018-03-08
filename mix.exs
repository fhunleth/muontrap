defmodule MuonTrap.MixProject do
  use Mix.Project

  def project do
    [
      app: :muontrap,
      version: "0.2.1",
      elixir: "~> 1.6",
      description: "Keep your ports contained",
      source_url: "https://github.com/fhunleth/muontrap",
      docs: [extras: ["README.md"], main: "readme"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_clean: ["clean"],
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps() do
    [
      {:elixir_make, "~> 0.4", runtime: false},
      {:ex_doc, "~> 0.11", only: :dev}
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
      maintainers: ["Frank Hunleth"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/fhunleth/muontrap"}
    ]
  end
end
