defmodule ArrayTest do
  use ExUnit.Case

  test "set/3" do
    list = for n <- 1..11, do: "v#{n}"
    array = Array.from_list(list)
    assert %Array{elements: elements} = Array.set(10, "new_value", array)
    assert elements |> elem(1) |> elem(0) == "new_value"
  end

  test "get/2" do
    for index <- 0..10 do
      list = for n <- 1..11, do: "v#{n}"
      array = Array.from_list(list)
      assert Array.get(index, array) == "v#{index + 1}"
    end
  end
end
