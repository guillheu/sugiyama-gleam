import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/set
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

type Laid =
  graph.Graph(
    String,
    #(String, Int, Int),
    #(option.Option(String), List(#(Int, Int))),
  )

fn layers(laid_out: Laid) -> dict.Dict(Int, List(#(String, Int))) {
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

// The waypoints routing the long A -> D edge should all share one
// x-coordinate, i.e. the long edge is drawn as a straight vertical line.
pub fn long_edge_is_straight_test() {
  let laid_out = sugiyama.run(get_graph())

  // The long edge (A -> D, possibly reversed by cycle-breaking) is the only
  // one that spans multiple layers, so it is the only one carrying waypoints.
  let assert [waypoints] =
    graph.get_edges(laid_out)
    |> list.filter_map(fn(e) {
      case e.label {
        option.Some(#(_label, [_, ..] as points)) -> Ok(points)
        _ -> Error(Nil)
      }
    })

  // It spans three layers, so it carries two waypoints, and every waypoint
  // lands on the same column.
  let chain_xs = list.map(waypoints, fn(point) { point.0 })
  assert chain_xs != []
  assert set.size(set.from_list(chain_xs)) == 1
}
