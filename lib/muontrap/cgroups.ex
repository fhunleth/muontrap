# SPDX-FileCopyrightText: 2018 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0

defmodule MuonTrap.Cgroups do
  @moduledoc false

  @cgroup_fs "/sys/fs/cgroup"

  @doc """
  Return true if it looks like the system has cgroup v2 support enabled
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
  Return the list of cgroup v2 controllers available at the unified hierarchy root
  """
  @spec get_controllers() :: {:ok, [String.t()]} | {:error, File.posix()}
  def get_controllers() do
    case File.read(Path.join(@cgroup_fs, "cgroup.controllers")) do
      {:ok, content} -> {:ok, content |> String.trim() |> String.split()}
      {:error, _} = error -> error
    end
  end

  @doc """
  Get a cgroup v2 interface file's contents (like cgget)
  """
  @spec cgget(String.t(), String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def cgget(cgroup_path, variable_name) do
    File.read(Path.join([@cgroup_fs, cgroup_path, variable_name]))
  end

  @doc """
  Write to a cgroup v2 interface file (like cgset)
  """
  @spec cgset(String.t(), String.t(), String.t()) :: :ok | {:error, File.posix()}
  def cgset(cgroup_path, variable_name, value) do
    File.write(Path.join([@cgroup_fs, cgroup_path, variable_name]), value)
  end

  # {map_key, file, type}. Map keys use underscores; the corresponding
  # interface file name is derived by replacing `_` with `.`.
  @config_fields [
    {:cpu_weight, "cpu.weight", :integer},
    {:cpu_max, "cpu.max", :cpu_max},
    {:cpu_idle, "cpu.idle", :boolean},
    {:memory_min, "memory.min", :bytes},
    {:memory_low, "memory.low", :bytes},
    {:memory_high, "memory.high", :bytes_or_max},
    {:memory_max, "memory.max", :bytes_or_max},
    {:memory_swap_max, "memory.swap.max", :bytes_or_max},
    {:memory_oom_group, "memory.oom.group", :boolean},
    {:pids_max, "pids.max", :count_or_max},
    {:io_weight, "io.weight", :integer},
    {:cpuset_cpus, "cpuset.cpus", :string},
    {:cpuset_mems, "cpuset.mems", :string}
  ]

  @doc """
  Read a snapshot of writable cgroup v2 interface files for `cgroup_path`.

  Returns a flat map keyed by atoms like `:cpu_weight`, `:memory_max`,
  ... (kernel file names with `.` replaced by `_`). Files that don't
  exist (controller not enabled, kernel doesn't support the knob) are
  omitted. A `nil` cgroup_path returns an empty map.
  """
  @spec config(String.t() | nil) :: %{optional(atom()) => term()}
  def config(nil), do: %{}

  def config(cgroup_path) do
    Enum.reduce(@config_fields, %{}, fn {key, file, type}, acc ->
      with {:ok, content} <- cgget(cgroup_path, file),
           {:ok, value} <- parse_config_value(type, content) do
        Map.put(acc, key, value)
      else
        _ -> acc
      end
    end)
  end

  @doc """
  Translate a cgroup config map into the controller list and `{controller,
  file, value_string}` settings list used by the muontrap port.

  Raises `ArgumentError` on unknown keys or malformed values.
  """
  @spec translate_config(map()) ::
          {[String.t()], [{String.t(), String.t(), String.t()}]}
  def translate_config(config) when is_map(config) do
    sets =
      Enum.map(config, fn {key, value} ->
        {file, type} =
          field_for(key) ||
            raise ArgumentError, "unknown cgroup config field: #{inspect(key)}"

        [controller | _] = String.split(file, ".", parts: 2)
        {controller, file, format_config_value!(type, value, key)}
      end)

    controllers = sets |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    {controllers, sets}
  end

  defp field_for(key) do
    Enum.find_value(@config_fields, fn
      {^key, file, type} -> {file, type}
      _ -> false
    end)
  end

  defp format_config_value!(:integer, n, _key) when is_integer(n), do: Integer.to_string(n)

  defp format_config_value!(:boolean, true, _key), do: "1"
  defp format_config_value!(:boolean, false, _key), do: "0"

  defp format_config_value!(:bytes, n, _key) when is_integer(n) and n >= 0,
    do: Integer.to_string(n)

  defp format_config_value!(:bytes_or_max, :max, _key), do: "max"

  defp format_config_value!(:bytes_or_max, n, _key) when is_integer(n) and n >= 0,
    do: Integer.to_string(n)

  defp format_config_value!(:count_or_max, :max, _key), do: "max"

  defp format_config_value!(:count_or_max, n, _key) when is_integer(n) and n >= 0,
    do: Integer.to_string(n)

  defp format_config_value!(:cpu_max, :max, _key), do: "max 100000"

  defp format_config_value!(:cpu_max, {quota, period}, _key)
       when is_integer(quota) and quota >= 0 and is_integer(period) and period > 0,
       do: "#{quota} #{period}"

  defp format_config_value!(:string, s, _key) when is_binary(s), do: s

  defp format_config_value!(_type, value, key) do
    raise ArgumentError, "invalid value for #{inspect(key)}: #{inspect(value)}"
  end

  defp parse_config_value(:integer, s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_config_value(:boolean, s) do
    case String.trim(s) do
      "0" -> {:ok, false}
      "1" -> {:ok, true}
      _ -> :error
    end
  end

  defp parse_config_value(:bytes, s), do: parse_config_value(:integer, s)

  defp parse_config_value(:bytes_or_max, s) do
    case String.trim(s) do
      "max" ->
        {:ok, :max}

      other ->
        case Integer.parse(other) do
          {n, ""} -> {:ok, n}
          _ -> :error
        end
    end
  end

  defp parse_config_value(:count_or_max, s), do: parse_config_value(:bytes_or_max, s)

  defp parse_config_value(:cpu_max, s) do
    case String.split(String.trim(s), " ", trim: true) do
      ["max", _period] ->
        {:ok, :max}

      [quota, period] ->
        with {q, ""} <- Integer.parse(quota),
             {p, ""} <- Integer.parse(period) do
          {:ok, {q, p}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_config_value(:string, s), do: {:ok, String.trim(s)}

  # {result key, interface file, parser}
  @stats [
    {:memory_current, "memory.current", :integer},
    {:memory_peak, "memory.peak", :integer},
    {:memory_events, "memory.events", :flat_keyed},
    {:memory_swap_current, "memory.swap.current", :integer},
    {:memory_pressure, "memory.pressure", :pressure},
    {:cpu_stat, "cpu.stat", :flat_keyed},
    {:cpu_pressure, "cpu.pressure", :pressure},
    {:pids_current, "pids.current", :integer},
    {:pids_peak, "pids.peak", :integer},
    {:pids_events, "pids.events", :flat_keyed},
    {:io_pressure, "io.pressure", :pressure},
    {:cgroup_stat, "cgroup.stat", :flat_keyed}
  ]

  @doc """
  Read a best-effort snapshot of the cgroup v2 stat files for `cgroup_path`.

  Returns a map keyed by stat name. Files that don't exist (e.g., a controller
  isn't enabled, or PSI isn't compiled in) are omitted rather than returned as
  errors. A `nil` `cgroup_path` returns an empty map.
  """
  @spec statistics(String.t() | nil) :: %{optional(atom()) => term()}
  def statistics(nil), do: %{}

  def statistics(cgroup_path) do
    Enum.reduce(@stats, %{}, fn {key, file, parser}, acc ->
      with {:ok, content} <- cgget(cgroup_path, file),
           {:ok, value} <- parse(parser, content) do
        Map.put(acc, key, value)
      else
        _ -> acc
      end
    end)
  end

  defp parse(:integer, content) do
    case Integer.parse(String.trim(content)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse(:flat_keyed, content) do
    map =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, &parse_flat_keyed_line/2)

    if map == %{}, do: :error, else: {:ok, map}
  end

  defp parse(:pressure, content) do
    map =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, &parse_pressure_line/2)

    if map == %{}, do: :error, else: {:ok, map}
  end

  defp parse_flat_keyed_line(line, acc) do
    with [key, value] <- String.split(line, " ", parts: 2),
         {n, ""} <- Integer.parse(value) do
      Map.put(acc, String.to_atom(key), n)
    else
      _ -> acc
    end
  end

  defp parse_pressure_line(line, acc) do
    case String.split(line, " ", trim: true) do
      [kind | fields] ->
        parsed = Enum.reduce(fields, %{}, &parse_pressure_field/2)
        if parsed == %{}, do: acc, else: Map.put(acc, String.to_atom(kind), parsed)

      _ ->
        acc
    end
  end

  defp parse_pressure_field(field, inner) do
    with [k, v] <- String.split(field, "=", parts: 2),
         {:ok, value} <- parse_pressure_value(v) do
      Map.put(inner, String.to_atom(k), value)
    else
      _ -> inner
    end
  end

  defp parse_pressure_value(v) do
    case Integer.parse(v) do
      {n, ""} ->
        {:ok, n}

      _ ->
        case Float.parse(v) do
          {f, ""} -> {:ok, f}
          _ -> :error
        end
    end
  end
end
