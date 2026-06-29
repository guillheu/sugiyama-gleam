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
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("B", "C"), "")
  |> graph.insert_edge(edge.new("A", "C"), "")
}

fn get_cyclic_graph() -> graph.Graph(String, String, String) {
  get_acyclic_graph()
  |> graph.insert_edge(edge.new("C", "A"), "")
}
