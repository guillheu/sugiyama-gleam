import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleeunit
import graph_utils

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn acyclic_check_test() {
  let graph = get_acyclic_graph()
  assert !graph_utils.has_cycles(graph)
}

pub fn cyclic_check_test() {
  let graph = get_cyclic_graph()
  assert graph_utils.has_cycles(graph)
}

fn get_acyclic_graph() -> graph.Graph(String, String, String) {
  graph.new()
  |> graph.insert_node(node.new("A", "A"))
  |> graph.insert_node(node.new("B", "B"))
  |> graph.insert_node(node.new("C", "C"))
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("B", "C"), "")
}

fn get_cyclic_graph() -> graph.Graph(String, String, String) {
  get_acyclic_graph()
  |> graph.insert_edge(edge.new("C", "A"), "")
}
