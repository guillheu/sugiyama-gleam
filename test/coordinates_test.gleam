import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import minimize_crossings.{type VertexType, Virtual}
import sugiyama

// A DAG with a long edge (A -> D spans three layers) so the layout has to
// route it through a chain of virtual vertices.
fn get_graph() -> graph.Graph(String, String, String) {
  graph.new()
  |> graph.insert_node(node.new("A", "A"))
  |> graph.insert_node(node.new("B", "B"))
  |> graph.insert_node(node.new("C", "C"))
  |> graph.insert_node(node.new("D", "D"))
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("B", "C"), "")
  |> graph.insert_edge(edge.new("C", "D"), "")
  |> graph.insert_edge(edge.new("A", "D"), "")
}

fn layers(
  laid_out: graph.Graph(VertexType(String), #(String, Int, Int), String),
) -> dict.Dict(Int, List(#(VertexType(String), Int))) {
  graph.get_nodes(laid_out)
  |> list.fold(dict.new(), fn(acc, n) {
    let #(_, layer, x) = n.value
    let current = result.unwrap(dict.get(acc, layer), [])
    dict.insert(acc, layer, [#(n.key, x), ..current])
  })
}

// No two vertices in the same layer may share an x-coordinate.
pub fn no_overlap_within_layer_test() {
  let laid_out = sugiyama.run(get_graph())

  dict.values(layers(laid_out))
  |> list.each(fn(row) {
    let xs = list.map(row, fn(entry) { entry.1 })
    assert list.length(xs) == set.size(set.from_list(xs))
  })
}

// The virtual vertices that route the long A -> D edge should all share one
// x-coordinate, i.e. the long edge is drawn as a straight vertical line.
pub fn long_edge_is_straight_test() {
  let laid_out = sugiyama.run(get_graph())

  let chain_xs =
    graph.get_nodes(laid_out)
    |> list.filter_map(fn(n) {
      let #(_, _, x) = n.value
      case n.key {
        Virtual(..) -> Ok(x)
        _ -> Error(Nil)
      }
    })

  // The chain exists and every vertex in it lands on the same column.
  assert chain_xs != []
  assert set.size(set.from_list(chain_xs)) == 1
}
