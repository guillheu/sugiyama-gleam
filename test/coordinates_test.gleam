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
    #(option.Option(String), #(#(Int, Int), #(Int, Int))),
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

// The control points of the long A -> D edge should share one x-coordinate
// with its endpoints, i.e. the long edge is drawn as a straight vertical line.
pub fn long_edge_is_straight_test() {
  let laid_out = sugiyama.run(get_graph())
  let positions =
    graph.get_nodes(laid_out)
    |> list.fold(dict.new(), fn(acc, n) {
      let #(_, layer, x) = n.value
      dict.insert(acc, n.key, #(x, layer))
    })

  // The long edge (A -> D, possibly reversed by cycle-breaking) is the only
  // one whose endpoints sit more than one layer apart.
  let assert [#(from, to, c1, c2)] =
    graph.get_edges(laid_out)
    |> list.filter_map(fn(e) {
      let assert Ok(from) = dict.get(positions, e.from)
      let assert Ok(to) = dict.get(positions, e.to)
      case e.label, to.1 - from.1 > 1 {
        option.Some(#(_label, #(c1, c2))), True -> Ok(#(from, to, c1, c2))
        _, _ -> Error(Nil)
      }
    })

  // Endpoints and both control points all land on the same column.
  let xs = [from.0, c1.0, c2.0, to.0]
  assert set.size(set.from_list(xs)) == 1

  // It spans three layers, so the control points are the two virtual
  // vertices routing it, one per intermediate layer.
  assert c1.1 == from.1 + 1
  assert c2.1 == to.1 - 1
}
