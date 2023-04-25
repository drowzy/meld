# Meld

A Request coalescing library for Elixir.

> Request coalescing is the practice of combining multiple requests for the same object into a single request to origin, 
> and then potentially using the resulting response to satisfy all pending requests.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `meld` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:meld, "~> 0.1.0"}
  ]
end
```
