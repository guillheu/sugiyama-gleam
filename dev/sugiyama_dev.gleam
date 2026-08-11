import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import minimize_crossings.{type VertexType, Real, Virtual}
import sugiyama

pub fn main() {
  get_cyclic_graph()
  |> sugiyama.run()
  |> print_layout
}

// Print the laid-out graph as rows of `key@x` entries, one row per layer,
// sorted left-to-right by the assigned x-coordinate.
fn print_layout(
  laid_out: graph.Graph(VertexType(String), #(String, Int, Int), String),
) -> Nil {
  let by_layer =
    graph.get_nodes(laid_out)
    |> list.fold(dict.new(), fn(acc, n) {
      let #(_, layer, x) = n.value
      let current = result.unwrap(dict.get(acc, layer), [])
      dict.insert(acc, layer, [#(n.key, x), ..current])
    })

  dict.keys(by_layer)
  |> list.sort(int.compare)
  |> list.each(fn(layer) {
    let row =
      result.unwrap(dict.get(by_layer, layer), [])
      |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
      |> list.map(fn(entry) { label(entry.0) <> "@" <> int.to_string(entry.1) })
      |> string.join(with: "  ")
    io.println("layer " <> int.to_string(layer) <> ": " <> row)
  })
}

fn label(vertex: VertexType(String)) -> String {
  case vertex {
    Real(key) -> key
    Virtual(from, to, index) ->
      "(" <> from <> "->" <> to <> ":" <> int.to_string(index) <> ")"
  }
}

fn get_acyclic_graph() -> graph.Graph(String, String, String) {
  graph.new()
  |> graph.insert_node(node.new("A", "A"))
  |> graph.insert_node(node.new("B", "B"))
  |> graph.insert_node(node.new("C", "C"))
  |> graph.insert_node(node.new("D", "D"))
  |> graph.insert_node(node.new("E", "E"))
  |> graph.insert_node(node.new("F", "F"))
  |> graph.insert_node(node.new("G", "G"))
  |> graph.insert_node(node.new("H", "H"))
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("A", "C"), "")
  |> graph.insert_edge(edge.new("B", "D"), "")
  |> graph.insert_edge(edge.new("C", "D"), "")
  |> graph.insert_edge(edge.new("C", "E"), "")
  |> graph.insert_edge(edge.new("D", "F"), "")
  |> graph.insert_edge(edge.new("E", "F"), "")
  |> graph.insert_edge(edge.new("E", "G"), "")
  |> graph.insert_edge(edge.new("F", "H"), "")
  |> graph.insert_edge(edge.new("G", "H"), "")
  // long edge — spans multiple layers, exercises virtual-vertex insertion
  |> graph.insert_edge(edge.new("A", "F"), "")
}

fn get_cyclic_graph() -> graph.Graph(String, String, String) {
  get_acyclic_graph()
  // long back edge
  |> graph.insert_edge(edge.new("H", "A"), "")
  // medium back edge
  |> graph.insert_edge(edge.new("F", "B"), "")
  // short back edge — forms a 2-cycle with C -> E
  |> graph.insert_edge(edge.new("E", "C"), "")
  // short back edge — forms a 2-cycle with C -> D
  |> graph.insert_edge(edge.new("D", "C"), "")
}
