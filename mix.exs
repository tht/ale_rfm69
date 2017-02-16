defmodule AleRFM69.Mixfile do
  use Mix.Project

  def project do
    [app: :ale_rfm69,
     version: "0.1.0",
     elixir: "~> 1.4",
     name: "ale_rfm69",
     description: description(),
     package: package(),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     docs: docs()]
  end

  # Configuration for the OTP application
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  defp description do
  """
  RFM69 driver for Elixir
  """
  end

  defp package do
    %{files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Thomas Lohmueller"],
      licenses: ["Unlicense"],
      links: %{"GitHub" => "https://github.com/tht/ale_rfm69"}}
  end

  # Dependencies can be Hex packages:
  defp deps do
    [
      {:elixir_ale, "~> 0.5.7"},
      {:ex_doc, "~> 0.11", only: :dev},
      {:remix, "~> 0.0.1", only: :dev}
    ]
  end

  defp docs do
    [ extras: ["README.md"] ]
  end
end
