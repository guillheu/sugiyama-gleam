import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/set

pub type VertexType(key) {
  Real(inner: key)
  Virtual(from: key, to: key, index: Int)
}

type LayerOrder(key) =
  dict.Dict(Int, List(VertexType(key)))

type Positions(key) =
  dict.Dict(VertexType(key), Int)

type IntermediateGraph(key, value, label) =
  graph.Graph(VertexType(key), #(value, Int), label)

const sweep_iterations: Int = 24

pub fn minimize(
  graph g: graph.Graph(key, #(value, Int), label),
) -> graph.Graph(VertexType(key), #(value, Int, Int), label) {
  let intermediate = insert_virtuals(g)
  let layers = bucket_by_layer(intermediate)
  let positions = positions_from_order(layers)
  let final_layers = sweep(intermediate, layers, positions, sweep_iterations)
  let final_positions = positions_from_order(final_layers)
  build_output(intermediate, final_positions)
}

// Phase 1. Build a fresh graph with `VertexType(key)` keys: every input
// node becomes `Real(k)`, and every edge that spans more than one layer
// is broken up by inserting `span - 1` virtual vertices carrying the
// source vertex's value. All resulting edges span exactly one layer.
fn insert_virtuals(
  g: graph.Graph(key, #(value, Int), label),
) -> IntermediateGraph(key, value, label) {
  let with_reals =
    graph.get_nodes(g)
    |> list.fold(graph.new(), fn(acc, n) {
      graph.insert_node(acc, node.new(Real(n.key), n.value))
    })

  graph.get_edges(g)
  |> list.fold(with_reals, fn(acc, e) {
    let assert Ok(from_node) = graph.get_node(g, e.from)
    let assert Ok(to_node) = graph.get_node(g, e.to)
    let #(from_val, from_layer) = from_node.value
    let #(_, to_layer) = to_node.value
    let span = to_layer - from_layer

    case span > 1 {
      True ->
        insert_virtual_chain(
          acc,
          e.from,
          e.to,
          from_val,
          from_layer,
          span,
          e.label,
        )
      False -> insert_labeled_edge(acc, Real(e.from), Real(e.to), e.label)
    }
  })
}

fn insert_virtual_chain(
  g: IntermediateGraph(key, value, label),
  from_key: key,
  to_key: key,
  from_val: value,
  from_layer: Int,
  span: Int,
  edge_label: option.Option(label),
) -> IntermediateGraph(key, value, label) {
  let with_virtuals =
    int.range(from: 1, to: span, with: g, run: fn(acc, i) {
      graph.insert_node(
        acc,
        node.new(Virtual(from_key, to_key, i), #(from_val, from_layer + i)),
      )
    })

  int.range(from: 0, to: span, with: with_virtuals, run: fn(acc, i) {
    let src = case i {
      0 -> Real(from_key)
      _ -> Virtual(from_key, to_key, i)
    }
    let dst = case i + 1 == span {
      True -> Real(to_key)
      False -> Virtual(from_key, to_key, i + 1)
    }
    insert_labeled_edge(acc, src, dst, edge_label)
  })
}

fn insert_labeled_edge(
  g: IntermediateGraph(key, value, label),
  from: VertexType(key),
  to: VertexType(key),
  edge_label: option.Option(label),
) -> IntermediateGraph(key, value, label) {
  let new_edge = case edge_label {
    option.Some(l) -> edge.new(from, to) |> edge.with_label(l)
    option.None -> edge.new(from, to)
  }
  let assert Ok(updated) = graph.try_insert_edge(g, new_edge)
  updated
}

// Phase 2. Bucket vertices by layer; initial in-layer order is the
// graph's node enumeration order.
fn bucket_by_layer(g: IntermediateGraph(key, value, label)) -> LayerOrder(key) {
  graph.get_nodes(g)
  |> list.fold(dict.new(), fn(acc, n) {
    let #(_, layer) = n.value
    let current = result.unwrap(dict.get(acc, layer), [])
    dict.insert(acc, layer, [n.key, ..current])
  })
  |> dict.map_values(fn(_, vs) { list.reverse(vs) })
}

fn positions_from_order(layers: LayerOrder(key)) -> Positions(key) {
  dict.fold(layers, dict.new(), fn(acc, _layer, vertices) {
    list.index_fold(vertices, acc, fn(inner_acc, v, i) {
      dict.insert(inner_acc, v, i)
    })
  })
}

// Phase 3. `iterations` down/up sweep pairs; positions are threaded
// through so we don't recompute them between passes.
fn sweep(
  g: IntermediateGraph(key, value, label),
  layers: LayerOrder(key),
  positions: Positions(key),
  iterations: Int,
) -> LayerOrder(key) {
  case iterations <= 0 {
    True -> layers
    False -> {
      let #(ls1, ps1) = down_sweep(g, layers, positions)
      let #(ls2, ps2) = up_sweep(g, ls1, ps1)
      sweep(g, ls2, ps2, iterations - 1)
    }
  }
}

fn down_sweep(
  g: IntermediateGraph(key, value, label),
  layers: LayerOrder(key),
  positions: Positions(key),
) -> #(LayerOrder(key), Positions(key)) {
  let sorted_layers = dict.keys(layers) |> list.sort(int.compare)
  case sorted_layers {
    [] -> #(layers, positions)
    [_, ..rest] ->
      list.fold(rest, #(layers, positions), fn(acc, l) {
        let #(ls, ps) = acc
        let vertices = result.unwrap(dict.get(ls, l), [])
        let reordered = reorder_layer(g, vertices, ps, True)
        #(
          dict.insert(ls, l, reordered),
          update_positions_for_layer(ps, reordered),
        )
      })
  }
}

fn up_sweep(
  g: IntermediateGraph(key, value, label),
  layers: LayerOrder(key),
  positions: Positions(key),
) -> #(LayerOrder(key), Positions(key)) {
  let sorted_layers =
    dict.keys(layers) |> list.sort(fn(a, b) { int.compare(b, a) })
  case sorted_layers {
    [] -> #(layers, positions)
    [_, ..rest] ->
      list.fold(rest, #(layers, positions), fn(acc, l) {
        let #(ls, ps) = acc
        let vertices = result.unwrap(dict.get(ls, l), [])
        let reordered = reorder_layer(g, vertices, ps, False)
        #(
          dict.insert(ls, l, reordered),
          update_positions_for_layer(ps, reordered),
        )
      })
  }
}

fn update_positions_for_layer(
  positions: Positions(key),
  vertices: List(VertexType(key)),
) -> Positions(key) {
  list.index_fold(vertices, positions, fn(acc, v, i) { dict.insert(acc, v, i) })
}

// Reorder a single layer by the median of neighbor positions in the
// adjacent layer. Vertices with no relevant neighbors keep their current
// position via a stable-sort fallback: their sort key is their own
// index, and ties break on the original index too.
fn reorder_layer(
  g: IntermediateGraph(key, value, label),
  vertices: List(VertexType(key)),
  positions: Positions(key),
  use_incoming: Bool,
) -> List(VertexType(key)) {
  vertices
  |> list.index_map(fn(v, i) {
    let sort_key = case neighbor_median(g, v, positions, use_incoming) {
      option.Some(f) -> f
      option.None -> int.to_float(i)
    }
    #(v, i, sort_key)
  })
  |> list.sort(fn(a, b) {
    let #(_, ai, ak) = a
    let #(_, bi, bk) = b
    case float.compare(ak, bk) {
      order.Eq -> int.compare(ai, bi)
      cmp -> cmp
    }
  })
  |> list.map(fn(t) { t.0 })
}

fn neighbor_median(
  g: IntermediateGraph(key, value, label),
  v: VertexType(key),
  positions: Positions(key),
  use_incoming: Bool,
) -> option.Option(Float) {
  case graph.get_node(g, v) {
    Error(_) -> option.None
    Ok(n) -> {
      let neighbor_keys = case use_incoming {
        True -> n.incoming
        False -> n.outgoing
      }
      neighbor_keys
      |> set.to_list
      |> list.filter_map(fn(k) { dict.get(positions, k) })
      |> median
    }
  }
}

fn median(values: List(Int)) -> option.Option(Float) {
  case values {
    [] -> option.None
    _ -> {
      let sorted = list.sort(values, int.compare)
      let n = list.length(sorted)
      let half = n / 2
      case n % 2 {
        0 ->
          case list.drop(sorted, half - 1) {
            [a, b, ..] ->
              option.Some({ int.to_float(a) +. int.to_float(b) } /. 2.0)
            _ -> option.None
          }
        _ ->
          case list.drop(sorted, half) {
            [m, ..] -> option.Some(int.to_float(m))
            _ -> option.None
          }
      }
    }
  }
}

// Phase 4. Copy every node from the intermediate graph, tagging it with
// its final `(value, layer, position)` triple; copy every edge unchanged.
fn build_output(
  g: IntermediateGraph(key, value, label),
  positions: Positions(key),
) -> graph.Graph(VertexType(key), #(value, Int, Int), label) {
  let with_nodes =
    graph.get_nodes(g)
    |> list.fold(graph.new(), fn(acc, n) {
      let #(v, layer) = n.value
      let p = result.unwrap(dict.get(positions, n.key), 0)
      graph.insert_node(acc, node.new(n.key, #(v, layer, p)))
    })

  graph.get_edges(g)
  |> list.fold(with_nodes, fn(acc, e) {
    let assert Ok(updated) = graph.try_insert_edge(acc, e)
    updated
  })
}
