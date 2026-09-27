import aonyx/graph
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import minimize_crossings.{type VertexType}

// Disconnected graphs.
//
// The layout phases in between these two functions each work on one
// connected piece at a time. That is not just an optimisation: crossing
// minimization and coordinate assignment both reason about "the vertices
// of a layer" as a single left-to-right row, and two components sharing a
// row compete for the same x-axis. Left alone they interleave — component
// A at x 0 and 2, component B at x 1 and 3 — and the drawing reads as one
// tangled graph instead of two separate ones.
//
// So `split` cuts the graph into its connected pieces before layout and
// `pack` puts them back afterwards, each shifted into its own horizontal
// band. A vertex with no edges at all is simply a component of size one
// and needs no special handling.
//
// Connectivity here ignores edge direction: `A -> B` keeps A and B
// together whichever way the arrow ends up pointing after cycle-breaking.

// Blank columns left between one component's band and the next.
const component_gap: Int = 2

/// Cut `graph` into its connected components, ignoring edge direction.
///
/// Every vertex lands in exactly one component and every edge is carried
/// along with its endpoints, so the components together hold the whole
/// graph. Vertices with no edges come back as single-vertex components.
/// The empty graph yields no components at all.
pub fn split(
  graph g: graph.Graph(key, value, label),
) -> List(graph.Graph(key, value, label)) {
  let nodes = graph.get_nodes(g)
  let neighbours =
    list.fold(nodes, dict.new(), fn(acc, n) {
      dict.insert(acc, n.key, node.get_neighbors(n))
    })
  let labels = label_components(nodes, neighbours)

  let node_buckets =
    list.fold(nodes, dict.new(), fn(acc, n) {
      let label = result.unwrap(dict.get(labels, n.key), 0)
      dict.insert(acc, label, [n, ..result.unwrap(dict.get(acc, label), [])])
    })
  let edge_buckets =
    graph.get_edges(g)
    |> list.fold(dict.new(), fn(acc, e) {
      // Both endpoints share a label, so either one picks the right bucket.
      let label = result.unwrap(dict.get(labels, e.from), 0)
      dict.insert(acc, label, [e, ..result.unwrap(dict.get(acc, label), [])])
    })

  dict.keys(node_buckets)
  |> list.sort(int.compare)
  |> list.map(fn(label) {
    let with_nodes =
      result.unwrap(dict.get(node_buckets, label), [])
      |> list.fold(graph.new(), fn(acc, n) {
        graph.insert_node(acc, node.new(n.key, n.value))
      })
    result.unwrap(dict.get(edge_buckets, label), [])
    |> list.fold(with_nodes, fn(acc, e) {
      let assert Ok(updated) = graph.try_insert_edge(acc, e)
      updated
    })
  })
}

// Number each vertex with the component it belongs to. Components are
// numbered in the order their first vertex appears, which keeps the
// output order a function of the input alone.
fn label_components(
  nodes: List(node.Node(key, value)),
  neighbours: dict.Dict(key, set.Set(key)),
) -> dict.Dict(key, Int) {
  let #(_, labels) =
    list.fold(nodes, #(0, dict.new()), fn(acc, n) {
      let #(next_label, labels) = acc
      case dict.has_key(labels, n.key) {
        True -> acc
        False -> #(
          next_label + 1,
          flood(neighbours, [n.key], next_label, labels),
        )
      }
    })
  labels
}

// Claim every vertex reachable from `frontier` for `label`.
fn flood(
  neighbours: dict.Dict(key, set.Set(key)),
  frontier: List(key),
  label: Int,
  labels: dict.Dict(key, Int),
) -> dict.Dict(key, Int) {
  case frontier {
    [] -> labels
    [key, ..rest] ->
      case dict.has_key(labels, key) {
        True -> flood(neighbours, rest, label, labels)
        False -> {
          let next =
            dict.get(neighbours, key)
            |> result.unwrap(set.new())
            |> set.to_list
          flood(
            neighbours,
            list.append(next, rest),
            label,
            dict.insert(labels, key, label),
          )
        }
      }
  }
}

/// Merge separately laid-out components into one graph, shifting each so
/// that it occupies its own range of x-coordinates.
///
/// Every component arrives with its own coordinates starting at x = 0, so
/// each is slid right past the ones before it, plus a gap. Layers are left
/// as they are: components all start at layer 0 and are drawn side by
/// side, not stacked.
pub fn pack(
  components: List(graph.Graph(VertexType(key), #(value, Int, Int), label)),
) -> graph.Graph(VertexType(key), #(value, Int, Int), label) {
  let #(packed, _) =
    list.fold(components, #(graph.new(), 0), fn(acc, component) {
      let #(merged, offset) = acc
      let nodes = graph.get_nodes(component)
      let with_nodes =
        list.fold(nodes, merged, fn(inner, n) {
          let #(value, layer, x) = n.value
          graph.insert_node(inner, node.new(n.key, #(value, layer, x + offset)))
        })
      let with_edges =
        graph.get_edges(component)
        |> list.fold(with_nodes, fn(inner, e) {
          let assert Ok(updated) = graph.try_insert_edge(inner, e)
          updated
        })
      #(with_edges, offset + width(nodes) + component_gap)
    })
  packed
}

// How many columns a component occupies. Its coordinates are normalized to
// start at x = 0, so this is its rightmost column plus one.
fn width(nodes: List(node.Node(VertexType(key), #(value, Int, Int)))) -> Int {
  list.fold(nodes, 0, fn(acc, n) {
    let #(_, _, x) = n.value
    int.max(acc, x + 1)
  })
}
