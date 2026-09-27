import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import minimize_crossings.{type VertexType, Real, Virtual}

// Final phase. Collapse the virtual-vertex chains back into real edges,
// so callers never see `VertexType` or the routing scaffolding.
//
// Crossing-minimization and coordinate assignment route every long edge
// through a chain of `Virtual` vertices, one per intermediate layer. Here
// we drop those vertices from the node set and instead condense their
// coordinates into the two control points of a cubic curve for the edge
// that spawned them: the first and the last vertex of the chain, as
// `#(x, y)` (where `y` is the layer index). A renderer can draw every edge
// as `source -> c1 -> c2 -> target` with no special-casing; a short edge
// (no virtuals) gets the points a third and two thirds of the way along
// the straight line between its endpoints, so it stays visually straight.
//
// The original edge label and weight are preserved: the label becomes
// `#(original_label, #(c1, c2))` and the weight is copied verbatim.

type Laid(key, value, label) =
  graph.Graph(VertexType(key), #(value, Int, Int), label)

pub type Routed(key, value, label) =
  graph.Graph(
    key,
    #(value, Int, Int),
    #(option.Option(label), #(#(Int, Int), #(Int, Int))),
  )

pub fn route(g: Laid(key, value, label)) -> Routed(key, value, label) {
  let nodes = graph.get_nodes(g)
  let chains = chain_index(nodes)
  let positions = position_index(nodes)

  let with_nodes =
    list.fold(nodes, graph.new(), fn(acc, n) {
      case n.key {
        Real(k) -> graph.insert_node(acc, node.new(k, n.value))
        // Virtual vertices are scaffolding; they become edge control points.
        Virtual(..) -> acc
      }
    })

  graph.get_edges(g)
  |> list.fold(with_nodes, fn(acc, e) {
    case e.from {
      // Interior chain edges (leaving a virtual vertex) are folded into
      // their edge's control points, so we skip them here.
      Virtual(..) -> acc
      Real(from_key) -> {
        let #(to_key, chain) = case e.to {
          Real(to) -> #(to, [])
          Virtual(from, to, _) -> #(
            to,
            result.unwrap(dict.get(chains, #(from, to)), []),
          )
        }
        let controls = controls(positions, from_key, to_key, chain)
        insert_edge(acc, from_key, to_key, #(e.label, controls), e.weight)
      }
    }
  })
}

/// Reattach the self-loops that `graph_utils.partition_self_loops` lifted
/// out before layout.
///
/// A self-loop has no span to route, so it gets control points that bulge
/// one column right and one layer down from the vertex it sits on. That
/// keeps it the same `source -> c1 -> c2 -> target` cubic as every other
/// edge — here a small loop below and to the right of the vertex — rather
/// than a degenerate zero-length line.
///
/// A loop on a vertex that is not in the graph is dropped.
pub fn add_self_loops(
  g: Routed(key, value, label),
  self_loops: List(edge.Edge(key, label)),
) -> Routed(key, value, label) {
  list.fold(self_loops, g, fn(acc, e) {
    case graph.get_node(acc, e.from) {
      Error(_) -> acc
      Ok(n) -> {
        let #(_, layer, x) = n.value
        let controls = #(#(x + 1, layer), #(x + 1, layer + 1))
        insert_edge(acc, e.from, e.to, #(e.label, controls), e.weight)
      }
    }
  })
}

// The two control points for an edge: the ends of its virtual-vertex
// chain, or — for a short edge, which has no chain — two points spaced
// evenly along the straight line joining its endpoints.
fn controls(
  positions: dict.Dict(key, #(Int, Int)),
  from: key,
  to: key,
  chain: List(#(Int, Int)),
) -> #(#(Int, Int), #(Int, Int)) {
  case chain {
    [first, ..rest] -> #(first, result.unwrap(list.last(rest), first))
    [] -> {
      let assert Ok(#(from_x, from_y)) = dict.get(positions, from)
      let assert Ok(#(to_x, to_y)) = dict.get(positions, to)
      #(
        #(thirds(from_x, to_x, 1), thirds(from_y, to_y, 1)),
        #(thirds(from_x, to_x, 2), thirds(from_y, to_y, 2)),
      )
    }
  }
}

// `count` thirds of the way from `a` to `b`, rounded to the nearest integer.
fn thirds(a: Int, b: Int, count: Int) -> Int {
  let delta = { b - a } * count
  case delta >= 0 {
    True -> a + { delta + 1 } / 3
    False -> a - { 1 - delta } / 3
  }
}

// Where each real vertex sits, as an `#(x, y)` point.
fn position_index(
  nodes: List(node.Node(VertexType(key), #(value, Int, Int))),
) -> dict.Dict(key, #(Int, Int)) {
  nodes
  |> list.fold(dict.new(), fn(acc, n) {
    case n.key {
      Real(key) -> {
        let #(_, layer, x) = n.value
        dict.insert(acc, key, #(x, layer))
      }
      Virtual(..) -> acc
    }
  })
}

// Group the virtual vertices of every long edge by its `#(from, to)`
// endpoints, ordered by chain index, as `#(x, y)` points.
fn chain_index(
  nodes: List(node.Node(VertexType(key), #(value, Int, Int))),
) -> dict.Dict(#(key, key), List(#(Int, Int))) {
  nodes
  |> list.fold(dict.new(), fn(acc, n) {
    case n.key {
      Virtual(from, to, index) -> {
        let #(_, layer, x) = n.value
        let current = result.unwrap(dict.get(acc, #(from, to)), [])
        dict.insert(acc, #(from, to), [#(index, x, layer), ..current])
      }
      Real(..) -> acc
    }
  })
  |> dict.map_values(fn(_, entries) {
    entries
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(entry) { #(entry.1, entry.2) })
  })
}

fn insert_edge(
  g: Routed(key, value, label),
  from: key,
  to: key,
  label: #(option.Option(label), #(#(Int, Int), #(Int, Int))),
  weight: option.Option(Float),
) -> Routed(key, value, label) {
  let new_edge =
    edge.new(from, to)
    |> edge.with_label(label)
    |> fn(e) {
      case weight {
        option.Some(w) -> edge.with_weight(e, w)
        option.None -> e
      }
    }
  let assert Ok(updated) = graph.try_insert_edge(g, new_edge)
  updated
}
