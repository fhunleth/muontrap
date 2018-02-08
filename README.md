# Shimmy

Keep your Erlang/Elixir port processes under control. This lightweight shim
protects you from port zombies. If you're on Linux and cgroups are available, it
can do cgroup things like limit memory and CPU utilization. As an added bonus,
it will kill all child processes when the port goes away so that processes can't
pollute the system with their daemons.

This is intended for long running processes or running commands. It currently
doesn't support sending input from Erlang and Elixir to the process that it's
running. That feature is possible to add, but you may be happier with other
solutions like [erlexec](https://github.com/saleyn/erlexec/) that have more
features for dealing with interactive processes. Output is passed back to
Erlang.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `shimmy` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:shimmy, "~> 0.1.0"}
  ]
end
```

## The problem

Erlang's port implementation expects the processes it launches to exit when
it closes stdin.

```elixir
System.cmd("/home/fhunleth/experiments/cgroup_test/cgroup_test", ["-p", "frank/foo", "-c", "cpu", "ping", "localhost"], into: IO.stream(:stdio, :line))
```

If you run `ping` without `shimmy`, you can watch it hang around even when if you kill
the process running `System.cmd`.

### Basic containment

Even if you don't make use of any cgroup controller features, having your port
processed contained can be useful just to make sure that all forked processes
are cleaned up on exit.

To set this up, first create a cgroup with appropriate permissions. Any path
will do; `shimmy` just needs to be able to create a subdirectory underneath it
for its use. For example:

```bash
sudo cgcreate -a fhunleth -g memory,cpu:mycgroup
```

Be sure to create the group for all of the cgroup controllers that you wish to
use with `shimmy`.

Next, in your Erlang or Elixir program, use `shimmy` in your port call and pass
the cgroup path and a subpath for use by the port process.

```bash
shimmy -p mycgroup/test -c cpu -c memory -- myprogram myargs
```

`shimmy` will start `myprogram` in the `cpu/mycgroup/test` and
`memory/mycgroup/test` groups. The cgroup parameters may be modified outside of
`shimmy` using `cgset` or my accessing the cgroup mountpoint manually. If you're
not going to do this, you only need to specify one controller.

On any error or if the Erlang VM closes the port or if `myprogram` exits,
`shimmy` will kill all OS processes in `mycgroup/test`. No need to worry about
random processes accumulating on your system.

### Limit CPU usage in a port

Imagine that you'd like all of your port process to be kept in a cgroup that is
limited to using 50% of a CPU. First, make sure that a cgroup exists with
sufficient permissions. Call that `mycgroup`. `shimmy` will create a subpath of
that group where it will move your port process. The `cpu.cfs_*` settings will
make it so that `myprogram` gets scheduled no more than 50 ms out of every 100
ms.

```bash
shimmy -p mycgroup/test -c cpu -s cpu.cfs_period_us=100000 -s cpu.cfs_quota_us=50000 -- myprogram myargs
```

## Limitations

If `stdin` isn't closed on `shimmy`, then it won't detect the the Erlang side
has gone away. If you invoke `shimmy` directly from `Port.open/2` or
`System.cmd/3`, this isn't a problem. However, `:os.cmd/1` starts a shell before
running the command and it won't close `stdin` on `shimmy`.
