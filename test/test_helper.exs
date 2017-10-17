ExUnit.start()

defmodule LapinTest.HelloWorldWorker do
  use Lapin.Worker, pattern: Lapin.Pattern.HelloWorld
end

defmodule LapinTest.WorkQueueWorker do
  use Lapin.Worker, pattern: Lapin.Pattern.WorkQueue
end
