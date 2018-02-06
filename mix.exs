defmodule Shimmy.MixProject do
  use Mix.Project

  def project do
    [
      app: :shimmy,
      version: "0.1.0",
      elixir: "~> 1.6",
      description: "Shim your ports",
      source_url: "https://github.com/fhunleth/shimmy",
      docs: [extras: ["README.md"], main: "readme"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_makefile: "Makefile",
      make_clean: ["clean"],
      package: package()
    ]
  end

  def application do
    []
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
        "test",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ],
      maintainers: ["Frank Hunleth"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/fhunleth/shimmy"}
    ]
  end

end
