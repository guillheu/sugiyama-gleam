import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import sugiyama

pub fn main() {
  get_cyclic_graph()
  |> sugiyama.run()
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
