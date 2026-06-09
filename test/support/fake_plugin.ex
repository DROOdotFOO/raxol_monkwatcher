defmodule Raxol.Monkwatcher.Test.FakePlugin do
  @moduledoc """
  Spins up a Unix Domain Socket listener that emits a scripted list of
  lines, then closes. Used by Plugin.Bridge tests to drive integration
  scenarios against the real wire format without mocking `:gen_tcp`.
  """

  @doc """
  Starts a UDS server at `socket_path` and emits each line in `lines`
  followed by `\\n`. Returns the spawned writer pid. Caller is expected
  to clean up `socket_path` afterward.
  """
  def start(socket_path, lines) when is_list(lines) do
    cleanup(socket_path)

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, socket_path}},
        {:active, false},
        {:reuseaddr, true},
        {:packet, :line}
      ])

    test_pid = self()

    writer =
      spawn_link(fn ->
        send(test_pid, :listening)

        case :gen_tcp.accept(listen, 1_000) do
          {:ok, sock} ->
            Enum.each(lines, fn line -> :gen_tcp.send(sock, line <> "\n") end)
            :gen_tcp.close(sock)

          {:error, _} ->
            :ok
        end

        :gen_tcp.close(listen)
      end)

    receive do
      :listening -> :ok
    after
      1_000 -> raise "FakePlugin failed to start listening at #{socket_path}"
    end

    writer
  end

  @doc "Returns a unique UDS path under /tmp for this test."
  def tmp_socket_path do
    base = System.tmp_dir!()
    name = "raxol_monkwatcher_#{System.unique_integer([:positive])}.sock"
    Path.join(base, name)
  end

  defp cleanup(path), do: _ = File.rm(path)
end
