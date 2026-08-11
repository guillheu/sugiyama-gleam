import aonyx/graph
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/set
import minimize_crossings.{type VertexType, Virtual}

// Horizontal coordinate assignment (the "priority method").
//
// The crossing-minimization phase leaves every vertex with an integer
// *rank* inside its layer (0, 1, 2, ...). That keeps edges from crossing
// but draws every layer flush-left, so edges zig-zag. This phase turns
// those ranks into x-coordinates that pull each vertex toward its
// neighbors, straightening edges — most importantly the long edges, which
// are chains of `Virtual` vertices we want laid out as vertical lines.
//
// For a fixed number of iterations we sweep down (aligning each vertex to
// the layer above) and up (aligning to the layer below). Within a layer,
// vertices are placed in order of decreasing priority: each one moves to
// the median x of its neighbors, but may only push vertices of strictly
// lower priority out of the way, and never past a minimum gap. `Virtual`
// vertices are given a priority higher than any real vertex can reach, so
// long-edge chains win their alignment and come out straight.

const iterations: Int = 8

const min_separation: Int = 1

// Higher than any real vertex's degree, so virtual vertices always win.
const virtual_priority: Int = 1_000_000

type LaidOut(key, value, label) =
  graph.Graph(VertexType(key), #(value, Int, Int), label)

type Layers(key) =
  dict.Dict(Int, List(VertexType(key)))

type Priorities(key) =
  dict.Dict(VertexType(key), Int)

type Xs(key) =
  dict.Dict(VertexType(key), Int)

pub fn straighten(g: LaidOut(key, value, label)) -> LaidOut(key, value, label) {
  let nodes = graph.get_nodes(g)
  let layers = bucket_by_layer(nodes)
  let priorities = priorities(nodes)
  let xs =
    list.fold(nodes, dict.new(), fn(acc, n) {
      let #(_, _, rank) = n.value
      dict.insert(acc, n.key, rank)
    })

  sweep(g, layers, priorities, xs, iterations)
  |> normalize
  |> write_back(g, _)
}

// Group node keys by layer, ordered left-to-right by their current rank.
fn bucket_by_layer(
  nodes: List(node.Node(VertexType(key), #(value, Int, Int))),
) -> Layers(key) {
  nodes
  |> list.fold(dict.new(), fn(acc, n) {
    let #(_, layer, _) = n.value
    let current = result.unwrap(dict.get(acc, layer), [])
    dict.insert(acc, layer, [n, ..current])
  })
  |> dict.map_values(fn(_, layer_nodes) {
    layer_nodes
    |> list.sort(fn(a, b) {
      let #(_, _, ra) = a.value
      let #(_, _, rb) = b.value
      int.compare(ra, rb)
    })
    |> list.map(fn(n) { n.key })
  })
}

fn priorities(
  nodes: List(node.Node(VertexType(key), #(value, Int, Int))),
) -> Priorities(key) {
  list.fold(nodes, dict.new(), fn(acc, n) {
    let priority = case n.key {
      Virtual(..) -> virtual_priority
      _ -> set.size(n.incoming) + set.size(n.outgoing)
    }
    dict.insert(acc, n.key, priority)
  })
}

fn sweep(
  g: LaidOut(key, value, label),
  layers: Layers(key),
  priorities: Priorities(key),
  xs: Xs(key),
  iterations: Int,
) -> Xs(key) {
  case iterations <= 0 {
    True -> xs
    False -> {
      let xs = down_sweep(g, layers, priorities, xs)
      let xs = up_sweep(g, layers, priorities, xs)
      sweep(g, layers, priorities, xs, iterations - 1)
    }
  }
}

// Top to bottom, aligning each layer to the one above it (incoming edges).
// The topmost layer has nothing above it, so it is skipped.
fn down_sweep(
  g: LaidOut(key, value, label),
  layers: Layers(key),
  priorities: Priorities(key),
  xs: Xs(key),
) -> Xs(key) {
  case dict.keys(layers) |> list.sort(int.compare) {
    [] -> xs
    [_, ..rest] ->
      list.fold(rest, xs, fn(acc, layer) {
        let vertices = result.unwrap(dict.get(layers, layer), [])
        place_layer(g, vertices, priorities, acc, True)
      })
  }
}

// Bottom to top, aligning each layer to the one below it (outgoing edges).
// The bottommost layer has nothing below it, so it is skipped.
fn up_sweep(
  g: LaidOut(key, value, label),
  layers: Layers(key),
  priorities: Priorities(key),
  xs: Xs(key),
) -> Xs(key) {
  case dict.keys(layers) |> list.sort(fn(a, b) { int.compare(b, a) }) {
    [] -> xs
    [_, ..rest] ->
      list.fold(rest, xs, fn(acc, layer) {
        let vertices = result.unwrap(dict.get(layers, layer), [])
        place_layer(g, vertices, priorities, acc, False)
      })
  }
}

// Place every vertex of a single layer. Vertices are handled in order of
// decreasing priority so that, by the time a vertex moves, every vertex
// that could block it (equal or higher priority) is already in its final
// spot and acts as a wall.
fn place_layer(
  g: LaidOut(key, value, label),
  vertices: List(VertexType(key)),
  priorities: Priorities(key),
  xs: Xs(key),
  use_incoming: Bool,
) -> Xs(key) {
  let count = list.length(vertices)
  let by_index =
    list.index_fold(vertices, dict.new(), fn(acc, v, i) {
      dict.insert(acc, i, v)
    })

  vertices
  |> list.index_map(fn(v, i) { #(v, i) })
  |> list.sort(fn(a, b) {
    let pa = result.unwrap(dict.get(priorities, a.0), 0)
    let pb = result.unwrap(dict.get(priorities, b.0), 0)
    case int.compare(pb, pa) {
      order.Eq -> int.compare(a.1, b.1)
      cmp -> cmp
    }
  })
  |> list.fold(xs, fn(acc, entry) {
    let #(v, i) = entry
    case desired_x(g, v, acc, use_incoming) {
      Error(Nil) -> acc
      Ok(target) -> move_vertex(by_index, priorities, acc, i, count, target)
    }
  })
}

// Where a vertex would like to sit: the median x of its neighbors in the
// adjacent layer. `Error` when it has no neighbors there (keep it put).
fn desired_x(
  g: LaidOut(key, value, label),
  v: VertexType(key),
  xs: Xs(key),
  use_incoming: Bool,
) -> Result(Int, Nil) {
  use n <- result.try(graph.get_node(g, v) |> result.replace_error(Nil))
  let neighbors = case use_incoming {
    True -> n.incoming
    False -> n.outgoing
  }
  neighbors
  |> set.to_list
  |> list.filter_map(fn(k) { dict.get(xs, k) })
  |> median
}

fn median(values: List(Int)) -> Result(Int, Nil) {
  case values {
    [] -> Error(Nil)
    _ -> {
      let sorted = list.sort(values, int.compare)
      let length = list.length(sorted)
      let middle = length / 2
      case length % 2 {
        0 ->
          case list.drop(sorted, middle - 1) {
            [a, b, ..] -> Ok({ a + b } / 2)
            _ -> Error(Nil)
          }
        _ ->
          case list.drop(sorted, middle) {
            [m, ..] -> Ok(m)
            _ -> Error(Nil)
          }
      }
    }
  }
}

fn move_vertex(
  by_index: dict.Dict(Int, VertexType(key)),
  priorities: Priorities(key),
  xs: Xs(key),
  index: Int,
  count: Int,
  target: Int,
) -> Xs(key) {
  let assert Ok(v) = dict.get(by_index, index)
  let current = result.unwrap(dict.get(xs, v), 0)
  let priority = result.unwrap(dict.get(priorities, v), 0)
  case int.compare(target, current) {
    order.Eq -> xs
    order.Gt ->
      move_right(by_index, priorities, xs, index, count, target, priority)
    order.Lt -> move_left(by_index, priorities, xs, index, target, priority)
  }
}

// Slide a vertex right toward `target`, pushing the lower-priority vertices
// on its right ahead of it, but no further than the first vertex of equal
// or higher priority (the "wall").
fn move_right(
  by_index: dict.Dict(Int, VertexType(key)),
  priorities: Priorities(key),
  xs: Xs(key),
  index: Int,
  count: Int,
  target: Int,
  priority: Int,
) -> Xs(key) {
  let assert Ok(v) = dict.get(by_index, index)
  let current = result.unwrap(dict.get(xs, v), 0)
  let wall = find_wall_right(by_index, priorities, index + 1, count, priority)
  let bound = case wall {
    Ok(w) -> {
      let assert Ok(wall_v) = dict.get(by_index, w)
      let wall_x = result.unwrap(dict.get(xs, wall_v), 0)
      wall_x - { w - index } * min_separation
    }
    Error(Nil) -> target
  }
  let new_x = int.max(current, int.min(target, bound))
  let stop = result.unwrap(wall, count)
  dict.insert(xs, v, new_x)
  |> push_right(by_index, _, index + 1, stop)
}

fn find_wall_right(
  by_index: dict.Dict(Int, VertexType(key)),
  priorities: Priorities(key),
  index: Int,
  count: Int,
  priority: Int,
) -> Result(Int, Nil) {
  case index >= count {
    True -> Error(Nil)
    False -> {
      let assert Ok(v) = dict.get(by_index, index)
      case result.unwrap(dict.get(priorities, v), 0) >= priority {
        True -> Ok(index)
        False ->
          find_wall_right(by_index, priorities, index + 1, count, priority)
      }
    }
  }
}

fn push_right(
  by_index: dict.Dict(Int, VertexType(key)),
  xs: Xs(key),
  index: Int,
  stop: Int,
) -> Xs(key) {
  case index >= stop {
    True -> xs
    False -> {
      let assert Ok(v) = dict.get(by_index, index)
      let assert Ok(previous) = dict.get(by_index, index - 1)
      let previous_x = result.unwrap(dict.get(xs, previous), 0)
      let x = result.unwrap(dict.get(xs, v), 0)
      let new_x = int.max(x, previous_x + min_separation)
      push_right(by_index, dict.insert(xs, v, new_x), index + 1, stop)
    }
  }
}

// Mirror of `move_right`: slide left, pushing lower-priority vertices on
// the left, stopped by the nearest wall of equal or higher priority.
fn move_left(
  by_index: dict.Dict(Int, VertexType(key)),
  priorities: Priorities(key),
  xs: Xs(key),
  index: Int,
  target: Int,
  priority: Int,
) -> Xs(key) {
  let assert Ok(v) = dict.get(by_index, index)
  let current = result.unwrap(dict.get(xs, v), 0)
  let wall = find_wall_left(by_index, priorities, index - 1, priority)
  let bound = case wall {
    Ok(w) -> {
      let assert Ok(wall_v) = dict.get(by_index, w)
      let wall_x = result.unwrap(dict.get(xs, wall_v), 0)
      wall_x + { index - w } * min_separation
    }
    Error(Nil) -> target
  }
  let new_x = int.min(current, int.max(target, bound))
  let stop = result.unwrap(wall, -1)
  dict.insert(xs, v, new_x)
  |> push_left(by_index, _, index - 1, stop)
}

fn find_wall_left(
  by_index: dict.Dict(Int, VertexType(key)),
  priorities: Priorities(key),
  index: Int,
  priority: Int,
) -> Result(Int, Nil) {
  case index < 0 {
    True -> Error(Nil)
    False -> {
      let assert Ok(v) = dict.get(by_index, index)
      case result.unwrap(dict.get(priorities, v), 0) >= priority {
        True -> Ok(index)
        False -> find_wall_left(by_index, priorities, index - 1, priority)
      }
    }
  }
}

fn push_left(
  by_index: dict.Dict(Int, VertexType(key)),
  xs: Xs(key),
  index: Int,
  stop: Int,
) -> Xs(key) {
  case index <= stop {
    True -> xs
    False -> {
      let assert Ok(v) = dict.get(by_index, index)
      let assert Ok(next) = dict.get(by_index, index + 1)
      let next_x = result.unwrap(dict.get(xs, next), 0)
      let x = result.unwrap(dict.get(xs, v), 0)
      let new_x = int.min(x, next_x - min_separation)
      push_left(by_index, dict.insert(xs, v, new_x), index - 1, stop)
    }
  }
}

// Shift every coordinate so the leftmost vertex sits at x = 0.
fn normalize(xs: Xs(key)) -> Xs(key) {
  case dict.values(xs) |> list.reduce(int.min) {
    Ok(minimum) -> dict.map_values(xs, fn(_, x) { x - minimum })
    Error(Nil) -> xs
  }
}

fn write_back(
  g: LaidOut(key, value, label),
  xs: Xs(key),
) -> LaidOut(key, value, label) {
  let with_nodes =
    graph.get_nodes(g)
    |> list.fold(graph.new(), fn(acc, n) {
      let #(value, layer, _) = n.value
      let x = result.unwrap(dict.get(xs, n.key), 0)
      graph.insert_node(acc, node.new(n.key, #(value, layer, x)))
    })

  graph.get_edges(g)
  |> list.fold(with_nodes, fn(acc, e) {
    let assert Ok(updated) = graph.try_insert_edge(acc, e)
    updated
  })
}
