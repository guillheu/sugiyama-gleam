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
// we drop those vertices from the node set and instead attach their
// coordinates to the edge that spawned them, as an ordered list of
// waypoints (`#(x, y)`, source -> target, where `y` is the layer index).
// A renderer can draw the edge as a smooth curve through those points;
// a short edge (no virtuals) simply carries an empty list.
//
// The original edge label and weight are preserved: the label becomes
// `#(original_label, waypoints)` and the weight is copied verbatim.

type Laid(key, value, label) =
  graph.Graph(VertexType(key), #(value, Int, Int), label)

pub type Routed(key, value, label) =
  graph.Graph(
    key,
    #(value, Int, Int),
    #(option.Option(label), List(#(Int, Int))),
  )

pub fn route(g: Laid(key, value, label)) -> Routed(key, value, label) {
  let nodes = graph.get_nodes(g)
  let waypoints = waypoint_index(nodes)

  let with_nodes =
    list.fold(nodes, graph.new(), fn(acc, n) {
      case n.key {
        Real(k) -> graph.insert_node(acc, node.new(k, n.value))
        // Virtual vertices are scaffolding; they become edge waypoints.
        Virtual(..) -> acc
      }
    })

  graph.get_edges(g)
  |> list.fold(with_nodes, fn(acc, e) {
    case e.from {
      // Interior chain edges (leaving a virtual vertex) are folded into
      // their edge's waypoint list, so we skip them here.
      Virtual(..) -> acc
      Real(from_key) -> {
        let #(to_key, points) = case e.to {
          Real(to) -> #(to, [])
          Virtual(from, to, _) -> #(
            to,
            result.unwrap(dict.get(waypoints, #(from, to)), []),
          )
        }
        insert_edge(acc, from_key, to_key, #(e.label, points), e.weight)
      }
    }
  })
}

// Group the virtual vertices of every long edge by its `#(from, to)`
// endpoints, ordered by chain index, as `#(x, y)` waypoints.
fn waypoint_index(
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
  label: #(option.Option(label), List(#(Int, Int))),
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
