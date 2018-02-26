# MuonTrap

[![Build Status](https://travis-ci.org/fhunleth/muontrap.svg?branch=master)](https://travis-ci.org/fhunleth/muontrap)
[![Hex version](https://img.shields.io/hexpm/v/muontrap.svg "Hex version")](https://hex.pm/packages/muontrap)

--> _Under active development_ <--

Keep programs, deamons, and applications launched from Erlang and Elixir
contained and well-behaved. This lightweight library kills OS processes if the
Elixir process running them crashes and if you're running on Linux, it can use
cgroups to prevent many other shenanigans.

Some other features:

* Set `cgroup` controls like thresholds on memory and CPU utilization
* Start OS processes as a different user or group
* Send SIGKILL to processes that aren't responsive to SIGTERM
* With `cgroups`, ensure that all children of launched processes have been killed too

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

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `muontrap` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:muontrap, "~> 0.1.0"}
  ]
end
```

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
processed contained can be useful just to make sure that all forked processes
are cleaned up on exit.

To set this up, first create a cgroup with appropriate permissions. Any path
will do; `muontrap` just needs to be able to create a subdirectory underneath it
for its use. For example:

```bash
sudo cgcreate -a fhunleth -g memory,cpu:mycgroup
```

Be sure to create the group for all of the cgroup controllers that you wish to
use with `muontrap`.

Next, in your Erlang or Elixir program, use `muontrap` in your port call and pass
the cgroup path and a subpath for use by the port process.

```bash
muontrap -g mycgroup/test -c cpu -c memory -- myprogram myargs
```

`muontrap` will start `myprogram` in the `cpu/mycgroup/test` and
`memory/mycgroup/test` groups. The cgroup parameters may be modified outside of
`muontrap` using `cgset` or my accessing the cgroup mountpoint manually. If you're
not going to do this, you only need to specify one controller.

On any error or if the Erlang VM closes the port or if `myprogram` exits,
`muontrap` will kill all OS processes in `mycgroup/test`. No need to worry about
random processes accumulating on your system.

### Limit CPU usage in a port

Imagine that you'd like all of your port process to be kept in a cgroup that is
limited to using 50% of a CPU. First, make sure that a cgroup exists with
sufficient permissions. Call that `mycgroup`. `muontrap` will create a subpath of
that group where it will move your port process. The `cpu.cfs_*` settings will
make it so that `myprogram` gets scheduled no more than 50 ms out of every 100
ms.

```bash
muontrap -g mycgroup/test -c cpu -s cpu.cfs_period_us=100000 -s cpu.cfs_quota_us=50000 -- myprogram myargs
```
