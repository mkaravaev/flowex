defmodule Flowex.Sync.Pipeline do
  defmacro __using__(_args) do
    quote do
      IO.inspect("Warning! You are using Sync behaviour in #{__MODULE__} pipeline!")

      import Flowex.Pipeline

      Module.register_attribute __MODULE__, :pipes, accumulate: true
      Module.register_attribute __MODULE__, :error_pipe, accumulate: false
      @error_pipe {:handle_error, 1, [], :error_pipe}

      @before_compile Flowex.Sync.Pipeline

      def init(opts), do: opts
      defoverridable [init: 1]

      def start(opts \\ %{}) do
        opts = init(opts)
        {:ok, sup_pid} = Flowex.Sync.Supervisor.start_link(__MODULE__, opts)
        do_start(sup_pid)
      end

      def stop(%Flowex.Pipeline{sup_pid: sup_pid}) do
        Enum.each(Supervisor.which_children(sup_pid), fn({id, _pid, :worker, [_]}) ->
          Supervisor.terminate_child(sup_pid, id)
        end)
        Supervisor.stop(sup_pid)
      end

      def supervised_start(pid, opts \\ %{}) do
        import Supervisor.Spec
        sup_spec = supervisor(Flowex.Sync.Supervisor, [__MODULE__, opts], [id: "Flowex.Sync_#{inspect __MODULE__}_#{inspect make_ref()}", restart: :permanent])
        {:ok, sup_pid} = Supervisor.start_child(pid, sup_spec)
         do_start(sup_pid)
      end

      defp do_start(sup_pid) do
        [{gen_server_name, _prod, :worker, [Flowex.Sync.GenServer]}] = Supervisor.which_children(sup_pid)
        %Flowex.Pipeline{in_name: gen_server_name, module: __MODULE__, out_name: gen_server_name, sup_pid: sup_pid}
      end

      def handle_error(error, _struct, _opts) do
        raise error
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def pipes, do: Enum.reverse(@pipes)
      def error_pipe, do: @error_pipe

      def pipe_info(name) do
        if pipe = Enum.find(pipes(), &(elem(&1, 0) == name)) do
          %{name: elem(pipe, 0), count: elem(pipe, 1), opts: elem(pipe, 2), type: elem(pipe, 3)}
        else
          nil
        end
      end

      def call(pipeline = %Flowex.Pipeline{in_name: in_name, out_name: out_name}, struct = %__MODULE__{}) do
        ip = %Flowex.IP{struct: Map.delete(struct, :__struct__)}
        ip = GenServer.call(in_name, ip)
        struct(%__MODULE__{}, ip.struct)
      end

      def cast(pipeline = %Flowex.Pipeline{in_name: in_name, out_name: out_name}, struct = %__MODULE__{}) do
        ip = %Flowex.IP{struct: Map.delete(struct, :__struct__)}
        GenServer.cast(in_name, ip)
      end
    end
  end
end
