defmodule RouterCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :router_core,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RouterCore, []}
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.9"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"}
    ]
  end

  defp releases do
    [
      router_core: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
