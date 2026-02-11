# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Cgroups do
  @moduledoc false

  @cgroup_fs "/sys/fs/cgroup"

  @doc """
  Return true if it looks like the system has cgroups support enabled
  """
  @spec cgroups_enabled?() :: boolean()
  def cgroups_enabled?() do
    case get_controllers() do
      {:ok, []} -> false
      {:ok, _list} -> true
      {:error, _anything} -> false
    end
  end

  @doc """
  Return a list available cgroup controllers
  """
  @spec get_controllers() :: {:ok, [String.t()]} | {:error, :enoent}
  def get_controllers() do
    case File.read("/sys/fs/cgroup/cgroup.controllers") do
      {:ok, content} ->
        controllers = content |> String.trim() |> String.split()
        {:ok, controllers}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get a cgroup variable (like cgget)
  """
  @spec cgget(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def cgget(_controller, cgroup_path, variable_name) do
    path = Path.join([@cgroup_fs, cgroup_path, variable_name])
    File.read(path)
  end

  @doc """
  Set a cgroup variable (like cgset)
  """
  @spec cgset(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, File.posix()}
  def cgset(_controller, cgroup_path, variable_name, value) do
    path = Path.join([@cgroup_fs, cgroup_path, variable_name])
    File.write(path, value)
  end
end
