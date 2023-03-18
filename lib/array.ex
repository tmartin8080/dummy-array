defmodule Array do
  @moduledoc """
  An Elixir Array implementation for simple get/set operations.
  """
  require Logger
  @default :undefined
  @leafsize 10
  @nodesize @leafsize

  defstruct [:size, :max, :elements, default: @default]

  @doc """
  NEW
  https://github.com/erlang/otp/blob/maint/lib/stdlib/src/array.erl#L256
  """
  def new, do: new([])
  def new(opts), do: new_0(opts, 0, false)

  def new(0, false, :undefined), do: %Array{size: 0, max: 10, elements: 10}

  def new(size, fixed?, default) do
    elements = find_max(size - 1, @leafsize)
    max = if fixed?, do: elements, else: 0
    %Array{size: size, max: max, default: default, elements: elements}
  end

  ########################################
  # new helpers
  ########################################
  defp new_0(opts, size, fixed?) when is_list(opts) do
    new_1(opts, size, fixed?, @default)
  end

  defp new_0(opts, size, fixed?) do
    new_1([opts], size, fixed?, @default)
  end

  defp new_1([:fixed | opts], size, _, default) do
    new_1(opts, size, true, default)
  end

  defp new_1([{:fixed, fixed?} | opts], size, _, default) when is_boolean(fixed?) do
    new_1(opts, size, fixed?, default)
  end

  defp new_1([{:default, default} | opts], size, fixed?, _) do
    new_1(opts, size, fixed?, default)
  end

  defp new_1([{:size, size} | opts], _, _, default) when is_integer(size) and size >= 0 do
    new_1(opts, size, true, default)
  end

  defp new_1([size | opts], _, _, default) when is_integer(size) and size >= 0 do
    new_1(opts, size, true, default)
  end

  defp new_1([], size, fixed?, default) do
    new(size, fixed?, default)
  end

  defp new_1(_opts, _size, _fixed?, _default) do
    :erlang.error(:badarg)
  end

  @doc """
  FROM_LIST
  https://github.com/erlang/otp/blob/maint/lib/stdlib/src/array.erl#L897-L920
  """
  def from_list(list), do: from_list(list, :undefined)

  def from_list([], default) do
    new({:default, default})
  end

  def from_list(list, default) when is_list(list) do
    {elements, size, max} = from_list_1(@leafsize, list, default, 0, [], [])
    %Array{size: size, max: max, elements: elements}
  end

  def from_list(_, _), do: :erlang.error(:badarg)

  ########################################
  # from_list helpers
  ########################################

  defp from_list_1(0, list, default, size, acc, ecc) do
    # reversing because elements were added onto the head
    elements = acc |> :lists.reverse() |> :erlang.list_to_tuple()

    result =
      case list do
        [] ->
          # list/leafs have been processed
          case ecc do
            # nodes have all been processed.
            [] -> {elements, size, @leafsize}
            _ -> from_list_2_0(size, [elements | ecc], @leafsize)
          end

        [_ | _] ->
          from_list_1(@leafsize, list, default, size, [], [elements | ecc])

        _ ->
          :erlang.error(:badarg)
      end

    result
  end

  defp from_list_1(leafsize, list, default, size, acc, ecc) do
    case list do
      # takes head and moves value in to acc
      [head | tail] -> from_list_1(leafsize - 1, tail, default, size + 1, [head | acc], ecc)
      # continues counting down leafsize setting default value to
      # fill out all leafs
      _ -> from_list_1(leafsize - 1, list, default, size, [default | acc], ecc)
    end
  end

  # Building the internal nodes (note that the input is reversed).
  def from_list_2_0(size, elements, leafsize) do
    padding = div(size - 1, leafsize) + 1
    padded = pad(padding, @nodesize, @leafsize, elements)
    from_list_2(@nodesize, padded, leafsize, size, [leafsize], [])
  end

  defp from_list_2(0, list, leafsize, size, acc, ecc) do
    elements = :erlang.list_to_tuple(acc)

    case list do
      [] ->
        case ecc do
          [] -> {elements, size, extend(leafsize)}
          _ -> from_list_2_0(size, :lists.reverse([elements | ecc]), extend(leafsize))
        end

      _ ->
        from_list_2(@nodesize, list, leafsize, size, [leafsize], [elements | ecc])
    end
  end

  defp from_list_2(nodesize, [head | tail], leafsize, size, acc, ecc) do
    from_list_2(nodesize - 1, tail, leafsize, size, [head | acc], ecc)
  end

  @doc """
  SET
  https://github.com/erlang/otp/blob/maint/lib/stdlib/src/array.erl#L560-L587
  """
  def set(index, value, array) when is_integer(index) and index >= 0 do
    %Array{size: size, max: max, default: default, elements: elements} = array

    cond do
      index < size ->
        %Array{array | elements: set_1(index, elements, value, default)}

      index < max ->
        # (note that this cannot happen if M == 0, since N >= 0)
        # A#array{size = I+1, elements = set_1(I, E, Value, D)};
        elements = set_1(index, elements, value, default)
        %Array{array | size: index + 1, elements: elements}

      max > 0 ->
        {new_elements, new_max} = grow(index, elements, max)
        elements = set_1(index, new_elements, value, default)
        %Array{array | size: index + 1, max: new_max, elements: elements}

      true ->
        :erlang.error(:badarg)
    end
  end

  def set(_index, _value, _array), do: :erlang.error(:badarg)

  ########################################
  # set helpers
  ########################################

  # handle node
  defp set_1(index, {_, _, _, _, _, _, _, _, _, _, s} = elements, value, default) do
    rem_index = rem(index, s)
    subtree_index = div(index, s) + 1
    element = :erlang.element(subtree_index, elements)
    value = set_1(rem_index, element, value, default)
    :erlang.setelement(subtree_index, elements, value)
  end

  # handle un-expanded or something?
  defp set_1(index, elements, value, default) when is_integer(elements) do
    expand(index, elements, value, default)
  end

  # handle leaf
  defp set_1(index, elements, value, _default) do
    :erlang.setelement(index + 1, elements, value)
  end

  # Enlarging the array upwards to accommodate an index `I'
  defp grow(index, elements, _M) when is_integer(elements) do
    new_max = find_max(index, elements)
    {new_max, new_max}
  end

  defp grow(index, elements, max), do: grow_1(index, elements, max)

  defp grow_1(index, elements, max) when index >= max do
    new_elements = :erlang.setelement(1, new_node(max), elements)
    grow_1(index, new_elements, extend(max))
  end

  defp grow_1(_index, elements, max), do: {elements, max}

  @doc """
  GET
  https://github.com/erlang/otp/blob/maint/lib/stdlib/src/array.erl#L624-L656
  """
  def get(index, array) when is_integer(index) and index >= 0 do
    %Array{size: size, max: max, elements: elements, default: default} = array
    counter_ref = :counters.new(1000, [:atomics])

    cond do
      index < size -> get_1(index, elements, default, counter_ref)
      max > 0 -> default
      true -> :erlang.error(:badarg)
    end
  end

  def get(_index, _array), do: :erlang.error(:badarg)

  ########################################
  # GET helpers
  ########################################

  defp get_1(index, {_, _, _, _, _, _, _, _, _, _, s} = elements, default, counter_ref) do
    rem_index = rem(index, s)
    subtree_index = div(index, s) + 1
    element = :erlang.element(subtree_index, elements)
    :counters.add(counter_ref, 1, 3)

    get_1(rem_index, element, default, counter_ref)
  end

  defp get_1(_index, elements, default, counter_ref) when is_integer(elements) do
    :counters.add(counter_ref, 1, 1)
    steps = :counters.get(counter_ref, 1)
    dbg(steps)
    default
  end

  defp get_1(index, elements, _D, counter_ref) do
    :counters.add(counter_ref, 1, 1)
    steps = :counters.get(counter_ref, 1)
    dbg(steps)
    :erlang.element(index + 1, elements)
  end

  ########################################
  # other helpers
  ########################################

  defp find_max(i, leafsize) when i >= leafsize, do: find_max(i, extend(leafsize))
  defp find_max(_i, leafsize), do: leafsize

  defp extend(leafsize), do: leafsize * @nodesize
  defp reduce(x), do: div(x, @nodesize)

  # left-padding a list elements with elements leafsize to the
  # nearest multiple of nodesize elements from padding.
  # (adding 0 to nodesize-1 elements).
  # pad(N, K, P, Es) ->
  #     push((K - (N rem K)) rem K, P, Es).
  defp pad(padding, nodesize, leafsize, elements) do
    n = rem(nodesize - rem(padding, nodesize), nodesize)
    push(n, leafsize, elements)
  end

  defp push(0, _elements, acc), do: acc
  defp push(n, elements, acc), do: push(n - 1, elements, [elements | acc])

  defp new_node(max) do
    :erlang.make_tuple(@nodesize + 1, max)
  end

  defp new_leaf(default) do
    :erlang.make_tuple(@leafsize, default)
  end

  #  Insert an element in an unexpanded node, expanding it as necessary.
  defp expand(index, size, value, default) when size > @leafsize do
    new_size = reduce(size)
    new_index = div(index, new_size) + 1
    idx = rem(index, new_size)
    new_value = expand(idx, new_size, value, default)
    :erlang.setelement(new_index, new_node(new_size), new_value)
  end

  defp expand(index, _size, value, default) do
    :erlang.setelement(index + 1, new_leaf(default), value)
  end
end
