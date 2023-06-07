# MuonTrap

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/fhunleth/muontrap/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/fhunleth/muontrap/tree/main)
[![Hex version](https://img.shields.io/hexpm/v/muontrap.svg "Hex version")](https://hex.pm/packages/muontrap)
[![REUSE status](https://api.reuse.software/badge/github.com/fhunleth/muontrap)](https://api.reuse.software/info/github.com/fhunleth/muontrap)

Keep programs, deamons, and applications launched from Erlang and Elixir
contained and well-behaved. This lightweight library kills OS processes if the
Elixir process running them crashes and if you're running on Linux, it can use
cgroups to prevent many other shenanigans.

Some other features:

* Attach your OS process to a supervision tree via a convenient `child_spec`
* Set `cgroup` controls like thresholds on memory and CPU utilization
* Start OS processes as a different user or group
* Send SIGKILL to processes that aren't responsive to SIGTERM
* With `cgroups`, ensure that all children of launched processes have been killed too

## TL;DR

Add `muontrap` to your project's `mix.exs` dependency list:

```elixir
def deps do
  [
    {:muontrap, "~> 1.0"}
  ]
end
```

Run a command similar to
[`System.cmd/3`](https://hexdocs.pm/elixir/System.html#cmd/3):

```elixir
iex>  MuonTrap.cmd("echo", ["hello"])
{"hello\n", 0}
```

Attach a long running process to a supervision tree using a
[child_spec](https://hexdocs.pm/elixir/Supervisor.html#module-child-specification)
like the following:

```elixir
{MuonTrap.Daemon, ["long_running_command", ["arg1", "arg2"], options]}
```

Running on Linux and can use cgroups? Then create a new cgroup:

```bash
sudo cgcreate -a $(whoami) -g memory:mycgroup
```

```elixir
{MuonTrap.Daemon,
 [
   "long_running_command",
   ["arg1", "arg2"],
   [cgroup_controllers: ["memory"], cgroup_base: "mycgroup"]
 ]}
```

`MuonTrap` will create a cgroup under "mycgroup" to run the
`"long_running_command"`. If the command fails, it will be restarted. If it
should no longer be running (like if something else crashed in Elixir and
supervision needs to clean up) then MuonTrap will kill `"long_running_command"`
and all of its children.

Want to know more? Read on...

## The problem

The Erlang VM's port interface lets Elixir applications run external programs.
This is important since it's not practical to rewrite everything in Elixir.
Plus, if the program is long running like a daemon or a server, you use Elixir
to supervise it and restart it on crashes. The catch is that the Erlang VM
expects port processes to be well-behaved. As you'd expect, many useful programs
don't quite meet the Erlang VM's expectations.

For example, let's say that you want to monitor a network connection and decide
that `ping` is the right tool. Here's how you could start `ping` in a process.

```elixir
iex> pid = spawn(fn -> System.cmd("ping", ["-i", "5", "localhost"], into: IO.stream(:stdio, :line)) end)
#PID<0.6116.0>
PING localhost (127.0.0.1): 56 data bytes
64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.032 ms
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.077 ms
```

To see that `ping` is running, call `ps` to look for it. You can also do this
from a separate terminal window outside of IEx:

```elixir
iex> :os.cmd('ps -ef | grep ping') |> IO.puts
  501 38820 38587   0  9:26PM ??         0:00.01 /sbin/ping -i 5 localhost
  501 38824 38822   0  9:27PM ??         0:00.00 grep ping
:ok
```

Now exit the Elixir process. Imagine here that in the real program that
something happened in Elixir and the process needs to exit and be restarted by a
supervisor.

```elixir
iex> Process.exit(pid, :oops)
true
iex> :os.cmd('ps -ef | grep ping') |> IO.puts
  501 38820 38587   0  9:26PM ??         0:00.02 /sbin/ping -i 5 localhost
  501 38833 38831   0  9:34PM ??         0:00.00 grep ping
```

As you can tell, `ping` is still running after the exit. If you run `:observer`
you'll see that Elixir did indeed terminate both the process and the port, but
that didn't stop `ping`. The reason for this is that `ping` doesn't pay
attention to `stdin` and doesn't notice the Erlang VM closing it to signal that
it should exit.

Imagine now that the process was supervised and it restarts. If this happens a
regularly, you could be running dozens of `ping` commands.

This is just one of the problems that `muontrap` fixes.

## Applicability

This is intended for long running processes. It's not great for interactive
programs that communicate via the port or send signals. That feature is possible
to add, but you'll probably be happier with other solutions like
[erlexec](https://github.com/saleyn/erlexec/).

## Running commands

The simplest way to use `muontrap` is as a replacement to `System.cmd/3`. Here's
an example using `ping`:

```elixir
iex> pid = spawn(fn -> MuonTrap.cmd("ping", ["-i", "5", "localhost"], into: IO.stream(:stdio, :line)) end)
#PID<0.30860.0>
PING localhost (127.0.0.1): 56 data bytes
64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.027 ms
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.081 ms
```

Now if you exit that process, `ping` gets killed as well:

```elixir
iex> Process.exit(pid, :oops)
true
iex> :os.cmd('ps -ef | grep ping') |> IO.puts
  501 38898 38896   0  9:58PM ??         0:00.00 grep ping

:ok
```

## Containment with cgroups

Even if you don't make use of any cgroup controller features, having your port
process contained can be useful just to make sure that everything is cleaned
up on exit including any subprocesses.

To set this up, first create a cgroup with appropriate permissions. Any path
will do; `muontrap` just needs to be able to create a subdirectory underneath it
for its use. For example:

```bash
sudo cgcreate -a $(whoami) -g memory,cpu:mycgroup
```

Be sure to create the group for all of the cgroup controllers that you wish to
use with `muontrap`. The above example creates it for the `memory` and `cpu`
controllers.

In Elixir, call `MuonTrap.cmd/3` with the
cgroup options now. In this case, we'll use the `cpu` controller, but this
example would work fine with any of the controllers.

```elixir
iex>  MuonTrap.cmd("spawning_program", [], cgroup_controllers: ["cpu"], cgroup_base: "mycgroup")
{"hello\n", 0}
```

In this example, `muontrap` runs `spawning_program` in a sub-cgroup under the
`cpu/mycgroup` group. The cgroup parameters may be modified outside of
`muontrap` using `cgset` or my accessing the cgroup mountpoint manually.

On any error or if the Erlang VM closes the port or if `spawning_program` exits,
`muontrap` will kill all OS processes in cgroup. No need to worry about
random processes accumulating on your system.

Note that if you use `cgroup_base`, a temporary cgroup is created for running
the command. If you want `muontrap` to use a particular cgroup and not create a
subgroup for the command, use the `:cgroup_path` option. Note that if you
explicitly specify a cgroup, be careful not to use it for anything else.
`MuonTrap` assumes that it owns the cgroup and when it needs to kill processes,
it kills all of them in the cgroup.

### Limit the memory used by a process

Linux's cgroups are very powerful and the examples here only scratch the
surface. If you'd like to limit an OS process and all of its child processes to
a maximum amount of memory, you can do that with the `memory` controller:

```elixir
iex>  MuonTrap.cmd("memory_hog", [], cgroup_controllers: ["memory"], cgroup_base: "mycgroup", cgroup_sets: [{"memory", "memory.limit_in_bytes", "268435456"}])
```

That line restricts the total memory used by `memory_hog` to 256 MB.

### Limit CPU usage in a port

Limiting the maximum CPU usage is also possible. Two parameters control that
with the `cpu` controller: `cpu.cfs_period_us` specifies the number of
microseconds in the scheduling period and `cpu.cfs_quota_us` specifies how many
of those microseconds can be used. Here's an example call that prevents a
program from using more than 50% of the CPU:

```elixir
iex>  MuonTrap.cmd("cpu_hog", [], cgroup_controllers: ["cpu"], cgroup_base: "mycgroup", cgroup_sets: [{"cpu", "cpu.cfs_period_us", "100000"}, {"cpu", "cpu.cfs_quota_us", 50000}])
```

## Supervision

For many long running programs, you may want to restart them if they crash.
Luckily Erlang already has mechanisms to do this. `MuonTrap` provides a
`GenServer` called `MuonTrap.Daemon` that you can hook into one of your
supervision trees.  For example, you could specify it like this in your
application's supervisor:

```elixir
  def start(_type, _args) do
    children = [
      {MuonTrap.Daemon, ["command", ["arg1", "arg2"], options]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
```

Supervisors provide three restart strategies, `:permanent`, `:temporary`, and
`:transient`. They work as follows:

* `:permanent` - Always restart the command if it exits or crashes. Restarts are
  limited to the Supervisor's restart intensity settings as they would be with
  normal `GenServer`s. This is the default.
* `:transient` - If the exit status of the command is 0 (i.e., success), then
  don't restart. Any other exit status is considered an error and the command is
  restarted.
* `:temporary` - Don't restart

If you're running more than one `MuonTrap.Daemon` under the same `Supervisor`,
then you'll need to give each one a unique `:id`. Here's an example `child_spec`
for setting the `:id` and the `:restart` parameters:

```elixir
    Supervisor.child_spec(
        {MuonTrap.Daemon, ["command", ["arg1"], options]},
         id: :my_daemon,
         restart: :transient
      )
```

## stdio flow control

The Erlang port feature does not implement flow control from messages coming
from the port process. Since `MuonTrap` captures stdio from the program being
run, it's possible that the program sends output so fast that it grows the
Elixir process's mailbox big enough to cause an out-of-memory error.

`MuonTrap` protects against this by implementing a flow control mechanism. When
triggered, the running program's stdout and stderr file handles won't be read
and hence it will eventually be blocked from writing to those handles.

The `:stdio_window` option specifies the maximum number of unacknowledged bytes
allowed. The default is 10 KB.

## muontrap development

In order to run the tests, some additional tools need to be installed.
Specifically the `cgcreate` and `cgget` binaries need to be installed (and
available on `$PATH`). Typically the package may be called `cgroup-tools` (on
arch linux you need to install the `libcgroup` aur package).

Then run:

```sh
sudo cgcreate -a $(whoami) -g memory,cpu:muontrap_test
```

## License

All original source code in this project is licensed under Apache-2.0.

Additionally, this project follows the [REUSE recommendations](https://reuse.software)
and labels so that licensing and copyright are clear at the file level.

Exceptions to Apache-2.0 licensing are:

* Configuration and data files are licensed under CC0-1.0
* Documentation is CC-BY-4.0
