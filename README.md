# MuonTrap

[![Hex version](https://img.shields.io/hexpm/v/muontrap.svg "Hex version")](https://hex.pm/packages/muontrap)
[![API docs](https://img.shields.io/hexpm/v/muontrap.svg?label=hexdocs "API docs")](https://hexdocs.pm/muontrap/MuonTrap.html)
[![CircleCI](https://dl.circleci.com/status-badge/img/gh/fhunleth/muontrap/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/fhunleth/muontrap/tree/main)
[![REUSE status](https://api.reuse.software/badge/github.com/fhunleth/muontrap)](https://api.reuse.software/info/github.com/fhunleth/muontrap)

Keep programs, daemons, and applications launched from Erlang and Elixir
contained and well-behaved. This lightweight library kills OS processes if the
Elixir process running them crashes and if you're running on Linux, it can use
cgroups to prevent many other shenanigans.

Some other features:

* Attach your OS process to a supervision tree via a convenient `child_spec`
* Set `cgroup` controls like thresholds on memory and CPU utilization
* Start OS processes as a different user or group
* Send SIGKILL to processes that aren't responsive to SIGTERM
* With `cgroups`, get lots of resource usage statistics on the process and all children

Importantly, LLMs have made the world more "exciting" in this area. MuonTrap
doesn't aim to provide the sandboxing they need. Look at tools like
[bubblewrap](https://github.com/containers/bubblewrap).

## TL;DR

Add `muontrap` to your project's `mix.exs` dependency list:

```elixir
def deps do
  [
    {:muontrap, "~> 2.0"}
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

If you're running on Linux or Nerves with cgroup v2 support enabled, set up a
parent cgroup once:

```elixir
# Enable the controllers you want
File.write!("/sys/fs/cgroup/cgroup.subtree_control", "+cpu +memory +pids")

# Create a parent directory MuonTrap can write under
File.mkdir_p!("/sys/fs/cgroup/mycgroup")
```

If the BEAM isn't running as root, you'll also need to `chown` the parent
directory so it's writable. See the [Setting up cgroup
v2](#setting-up-cgroup-v2) section for the full setup.

```elixir
{MuonTrap.Daemon,
 [
   "long_running_command",
   ["arg1", "arg2"],
   [cgroup_base: "mycgroup", cgroup: %{memory_max: 500_000_000}]
 ]}
```

`MuonTrap` will create a sub-cgroup under `mycgroup` to run
`long_running_command`. If the command fails, it will be restarted. If it
should no longer be running (e.g., something crashed in Elixir and supervision
is cleaning up), then MuonTrap will kill `long_running_command` and all of its
children.

> MuonTrap 2.0 dropped cgroup v1. v2 (the unified hierarchy) is commonly
> available these days. If you're stuck on v1, pin to MuonTrap 1.x.

Want to know more about the motivations for this library? Read on in the
[Background](#background) section.

## FAQ

### How do I watch stdout?

If you're using `MuonTrap.cmd/3`, you don't get the called program's output
until after it exits. Just like `System.cmd/3`, the `:into` option can be used
to get the output as it's printed. Here's an example.

```elixir
MuonTrap.cmd("my_program", [], stderr_to_stdout: true, into: IO.binstream(:stdio, :line))
```

If you're using `MuonTrap.Daemon`, then the best way is to send output to the
logger. There are quite a few options, so see the `MuonTrap.Daemon` docs on what
makes sense for you.

### How do I stop a MuonTrap.Daemon?

Treat the `MuonTrap.Daemon` process just like any other Elixir process. If you
put it in a supervision tree, call `Supervisor.terminate_child/2`. If you have
it's pid, call `Process.exit/2`.

### How do I delay a daemon until a dependency is ready?

Pass a 0-arity function via the `:wait_for` option. It runs in a linked `Task`
before the OS process is launched, so it can block (e.g., poll a TCP port or
wait on a file) without holding up the supervisor. The Daemon launches the
command once the function returns; if it raises, the link tears the Daemon
down and the supervisor's restart policy applies.

```elixir
{MuonTrap.Daemon,
 ["my_server", [],
  [wait_for: fn -> wait_for_tcp_port("db", 5432) end]]}
```

## Background

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

Even if you don't set any controller limits, putting your port process in a
cgroup is useful by itself: when MuonTrap tears down the cgroup, every
descendant process inside it dies too — no orphaned children, no escapees.

### Setting up cgroup v2

MuonTrap requires cgroup v2 (the unified hierarchy at `/sys/fs/cgroup`). Two
pieces of one-time setup:

**1. Enable the controllers you need at the root.** A controller has to be
enabled in a cgroup's `cgroup.subtree_control` before it's available to the
children of that cgroup. Most users will do this once at the root:

```bash
echo +cpu +memory +pids | sudo tee /sys/fs/cgroup/cgroup.subtree_control
```

or

```elixir
File.write!("/sys/fs/cgroup/cgroup.subtree_control", "+cpu +memory +pids")
```

This only needs to happen before MuonTrap launches its first cgroup-using
process — there's no need to wire it into early boot. On Nerves, where the
BEAM runs as root, calling `File.write!/2` from an application start
callback works fine.

On systemd hosts, systemd manages `cgroup.subtree_control` — usually the
easiest path is to put your application in a slice with `Delegate=yes`,
`CPUAccounting=yes`, `MemoryAccounting=yes`, etc., and point `cgroup_base`
at that slice's directory. See `man 5 systemd.resource-control`.

Required kernel options on Nerves: `CONFIG_CGROUPS`, `CONFIG_MEMCG`,
`CONFIG_CFS_BANDWIDTH`, `CONFIG_CGROUP_PIDS`. Some official Nerves systems
have this enabled already. If you're on the Raspberry Pi, the bootloader turns
off memory cgroups by default since there's a ~1% overhead when enabled.

**2. Create a parent directory MuonTrap can write to.** Any path under
`/sys/fs/cgroup` works; MuonTrap creates a sub-cgroup beneath it.

```bash
sudo mkdir -p /sys/fs/cgroup/mycgroup
sudo chown -R $(whoami) /sys/fs/cgroup/mycgroup
```

If MuonTrap can't find the controllers it needs, it will exit with a clear
error and tell you which controller is missing.

### Running a command in a cgroup

```elixir
MuonTrap.cmd("spawning_program", [], cgroup_base: "mycgroup", cgroup: %{cpu_weight: 100})
```

MuonTrap creates a temporary sub-cgroup under `mycgroup`, runs the program in
it, and tears it down on exit. Controllers are enabled automatically based on
which keys are present in the `:cgroup` map (here, `cpu.*` → the `cpu`
controller). If you want a fixed path, use `:cgroup_path` instead — but make
sure nothing else uses that cgroup, since MuonTrap kills everything in it on
cleanup.

### Cap the memory used by a process

```elixir
iex> MuonTrap.cmd("memory_hog", [],
       cgroup_base: "mycgroup",
       cgroup: %{memory_max: 268_435_456})
```

That restricts total memory to 256 MB. When the limit is hit, the kernel
invokes the OOM killer; if you also want the *whole cgroup* to be killed
together (rather than one process at a time), set `memory.oom.group`:

```elixir
cgroup: %{memory_max: 268_435_456, memory_oom_group: true}
```

### Cap CPU usage

In v2, CPU bandwidth is controlled by `cpu.max`, expressed as `{quota_us,
period_us}`. Limit a process to 50% of one CPU:

```elixir
iex> MuonTrap.cmd("cpu_hog", [],
       cgroup_base: "mycgroup",
       cgroup: %{cpu_max: {50_000, 100_000}})
```

### Cap the number of processes (anti-fork-bomb)

```elixir
cgroup: %{pids_max: 200}
```

Useful when you're running something that might fork uncontrollably (a
compromised browser, an LLM-driven shell, a flaky third-party binary).

### Reading current usage and configuration

`MuonTrap.Daemon.statistics/1` returns a snapshot of the daemon's output
counters and every readable cgroup stat file in one map (memory usage and
peak, CPU and memory PSI, OOM-kill counts, `pids.current`, etc.):

```elixir
%{
  output_byte_count: 295,
  memory_current: 552_222_720, memory_peak: 555_364_352,
  memory_events: %{oom_kill: 0, ...},
  cpu_stat: %{usage_usec: 867_248_613, ...},
  cpu_pressure: %{some: %{avg10: 0.0, ...}, full: %{...}},
  pids_current: 42, pids_peak: 52,
  ...
} = MuonTrap.Daemon.statistics(daemon_pid)
```

`MuonTrap.Daemon.cgroup_config/1` returns the writable side in the same
shape you'd pass to `:cgroup`, so a running daemon's settings can be
cloned into a new one:

```elixir
%{memory_max: 268_435_456,
  cpu_weight: 100} = MuonTrap.Daemon.cgroup_config(daemon_pid)

"mycgroup/abc"   = MuonTrap.Daemon.cgroup_path(daemon_pid)
```

For anything outside this set, use the generic interface:

```elixir
{:ok, raw} = MuonTrap.Daemon.cgget(daemon_pid, "memory.peak")
:ok        = MuonTrap.Daemon.cgset(daemon_pid, "memory.max", "536870912")
```

The full list of v2 interface files is in `man 7 cgroups` and the kernel's
[`Documentation/admin-guide/cgroup-v2.rst`](https://docs.kernel.org/admin-guide/cgroup-v2.html).

## Sandboxing a process (browser, LLM workspace, untrusted binaries)

Cgroups give you **resource limits**, not **isolation**. A process that's been
capped at 256 MB still has full filesystem, network, and syscall access — if
it gets compromised, the attacker can read your secrets, exfiltrate over the
network, and so on. For real isolation you need namespaces (mount, PID, net,
user, IPC, UTS), seccomp filters, and dropped capabilities.

The simplest way to get that on Linux is [bubblewrap
(`bwrap`)](https://github.com/containers/bubblewrap) — a small setuid helper
used by Flatpak. Layer it under MuonTrap: MuonTrap handles lifecycle and
resource caps, `bwrap` handles isolation.

```elixir
{MuonTrap.Daemon,
 [
   "bwrap",
   [
     "--ro-bind", "/usr", "/usr",
     "--ro-bind", "/lib", "/lib",
     "--ro-bind", "/lib64", "/lib64",
     "--proc", "/proc",
     "--dev", "/dev",
     "--bind", "/tmp/browser-home", "/home/browser",
     "--unshare-all",
     "--die-with-parent",
     "--",
     "/usr/bin/my-browser"
   ],
   [
     cgroup_base: "mycgroup",
     cgroup: %{
       memory_max: 536_870_912,
       memory_oom_group: true,
       cpu_max: {50_000, 100_000},
       pids_max: 200
     }
   ]
 ]}
```

`--die-with-parent` ensures `bwrap` (and its child) dies if MuonTrap dies, and
`--unshare-all` puts the program in fresh namespaces so it can't see other
processes, your real network stack, or the rest of your filesystem.

For LLM agents that run untrusted code, the same pattern applies, but you
likely also want filesystem rollback (overlayfs scratch dir) and a tighter
network policy. MuonTrap handles only the lifecycle + resource caps piece;
for the rest, look at `bwrap`, [`nsjail`](https://github.com/google/nsjail),
or container runtimes (Podman, Firecracker microVMs).

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

The cgroup-tagged tests need a `muontrap_test` cgroup with the `cpu` and
`memory` controllers available:

```sh
# One-time root setup (skip if your system or systemd already enables these):
echo +cpu +memory | sudo tee /sys/fs/cgroup/cgroup.subtree_control

sudo mkdir -p /sys/fs/cgroup/muontrap_test
sudo chown -R $(whoami) /sys/fs/cgroup/muontrap_test
```

To skip cgroup-tagged tests entirely (e.g., on macOS), run
`mix test --exclude cgroup`.

## License

All original source code in this project is licensed under Apache-2.0.

Additionally, this project follows the [REUSE recommendations](https://reuse.software)
and labels so that licensing and copyright are clear at the file level.

Exceptions to Apache-2.0 licensing are:

* Configuration and data files are licensed under CC0-1.0
* Documentation is CC-BY-4.0
