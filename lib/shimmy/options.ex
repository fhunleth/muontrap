defmodule Shimmy.Options do
  def to_args(options), do: to_args(options, [], [])

  defp to_args([], args, opts), do: {args, opts}

  defp to_args([{:cgroup_controllers, controllers} | rest], args, opts) do
    new_args = controllers_to_args(controllers, [])
    to_args(rest, new_args ++ args, opts)
  end

  defp to_args([{:cgroup_path, path} | rest], args, opts) do
    to_args(rest, ["--path", path | args], opts)
  end

  defp to_args([{:delay_to_sigkill, delay} | rest], args, opts) do
    to_args(rest, ["--delay-to-sigkill", "#{delay}" | args], opts)
  end

  defp to_args([{:cgroup_sets, sets} | rest], args, opts) do
    new_args = sets_to_args(sets, [])
    to_args(rest, new_args ++ args, opts)
  end

  defp to_args([{:uid, uid} | rest], args, opts) do
    to_args(rest, ["--uid", "#{uid}" | args], opts)
  end

  defp to_args([{:gid, gid} | rest], args, opts) do
    to_args(rest, ["--gid", "#{gid}" | args], opts)
  end

  defp to_args([other | rest], args, opts) do
    to_args(rest, args, [other | opts])
  end

  defp controllers_to_args([], args), do: args

  defp controllers_to_args([controller | rest], args) do
    new_args = ["--controller", controller | args]
    controllers_to_args(rest, new_args)
  end

  defp sets_to_args([], args), do: args

  defp sets_to_args([controller | rest], args) do
    new_args = ["--set", controller | args]
    controllers_to_args(rest, new_args)
  end
end
