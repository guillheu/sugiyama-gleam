import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/list
import gleeunit
import graph_utils

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn acyclic_check_test() {
  let graph = get_acyclic_graph()
  assert !has_cycles(graph)
}

pub fn cyclic_check_test() {
  let graph = get_cyclic_graph()
  assert has_cycles(graph)
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

pub fn has_cycles(graph: graph.Graph(key, value, label)) -> Bool {
  list.any(graph.get_nodes(graph), fn(next_vertex) {
    has_cycles_recurse([next_vertex], next_vertex, graph)
  })
}

fn has_cycles_recurse(
  traversed_nodes: List(node.Node(key, value)),
  current_node: node.Node(key, value),
  graph: graph.Graph(key, value, label),
) -> Bool {
  let outgoing_edges =
    graph_utils.get_outgoing_edges(current_node, graph.get_edges(graph))

  list.any(outgoing_edges, fn(outgoing_edge) {
    let assert Ok(node_destination) = graph.get_node(graph, outgoing_edge.to)
    case list.contains(traversed_nodes, node_destination) {
      True -> True
      False ->
        has_cycles_recurse(
          [current_node, ..traversed_nodes],
          node_destination,
          graph,
        )
    }
  })
}
