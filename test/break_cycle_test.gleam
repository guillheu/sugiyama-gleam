import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import break_cycle
import sugiyama_test

pub fn break_cycle_test() {
  let start_graph = get_cyclic_graph()
  let graph_no_cycles = break_cycle.berger_shor(start_graph)
  assert !sugiyama_test.has_cycles(graph_no_cycles)
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
