defmodule Meld.Error do
  defexception message: "Error during action execution", stack: nil, key: nil
end
