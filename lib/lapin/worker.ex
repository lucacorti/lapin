defmodule Lapin.Worker do
  @moduledoc """
  Lapin Worker behaviour

  To Implement a custom `Lapin.Worker` behaviour define a module:

  ```
  defmodule MyApp.MyWorker do
    use Lapin.Worker

    [... callbacks implementation ...]
  end
  ```

  A custom `Lapin.Pattern` module can be specified using the `pattern` option:

  ```
  defmodule MyApp.MyWorker do
    use Lapin.Worker, pattern: MyApp.MyPattern

    [... callbacks implementation ...]
  end
  ```

  Check out the `Lapin.Pattern` submodules for a number of implementantions of
  common interaction patterns.
  """
  alias Lapin.{Message, Connection}

  @typedoc """
  Module conforming to `Lapin.Pattern`
  """
  @type pattern :: Lapin.Pattern

  @typedoc """
  Exchange name
  """
  @type exchange :: String.t

  @typedoc """
  Queue name
  """
  @type queue :: String.t

  @typedoc """
  Channel role
  """
  @type role :: :consumer | :producer

  @typedoc """
  Worker module callback result
  """
  @type on_callback :: :ok | {:error, message :: String.t}

  @doc """
  Returns the pattern for the worker module, defaults to `Lapin.Pattern`
  """
  @callback pattern() :: pattern

  @doc """
  Called when receiving a `basic.cancel` from the broker.
  """
  @callback handle_cancel(channel_config :: Connection.channel_config) :: on_callback

  @doc """
  Called when receiving a `basic.cancel_ok` from the broker.
  """
  @callback handle_cancel_ok(channel_config :: Connection.channel_config) :: on_callback

  @doc """
  Called when receiving a `basic.deliver` from the broker.

  Message consumption is successfully completed when this callback returns `:ok`
  """
  @callback handle_deliver(channel_config :: Connection.channel_config, message :: Message.t) :: on_callback

  @doc """
  Called when receiving a `basic.consume_ok` from the broker.

  This signals successul registration as a consumer.
  """
  @callback handle_consume_ok(channel_config :: Connection.channel_config) :: on_callback

  @doc """
  Called when completing a `basic.publish` with the broker.

  Message transmission to the broker is successful when this callback is called.
  """
  @callback handle_publish(channel_config :: Connection.channel_config, message :: Message.t) :: on_callback

  @doc """
  Called when receiving a `basic.return` from the broker.

  THis signals an undeliverable returned message from the broker.
  """
  @callback handle_return(channel_config :: Connection.channel_config, message :: Message.t) :: on_callback

  defmacro __using__(options) do
    pattern = Keyword.get(options, :pattern, Lapin.Pattern)
    quote bind_quoted: [pattern: pattern] do
      @behaviour Lapin.Worker
      alias Lapin.Message

      @pattern pattern
      def pattern(), do: @pattern

      def handle_cancel(_channel_config), do: :ok
      def handle_cancel_ok(_channel_config), do: :ok
      def handle_deliver(_channel_config, _message), do: :ok
      def handle_publish(_channel_config, _message), do: :ok
      def handle_consume_ok(_channel_config), do: :ok
      def handle_return(_channel_config, _message), do: :ok

      defoverridable [handle_cancel: 1, handle_cancel_ok: 1, handle_deliver: 2,
                      handle_publish: 2, handle_consume_ok: 1, handle_return: 2]
    end
  end
end
