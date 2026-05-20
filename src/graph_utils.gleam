import aonyx/graph
import aonyx/graph/edge
import gleam/option.{None, Some}
import gleam/result

pub fn reverse_edge(e: edge.Edge(key, label)) -> edge.Edge(key, label) {
  edge.new(e.to, e.from)
  |> case e.label {
    Some(label) -> edge.with_label(_, label)
    None -> edge.without_label
  }
  |> case e.weight {
    Some(weight) -> edge.with_weight(_, weight)
    None -> edge.without_weight
  }
}

pub fn reverse_edge_in(
  graph: graph.Graph(key, value, label),
  from: key,
  to: key,
) -> Result(graph.Graph(key, value, label), Nil) {
  use edge_to_reverse <- result.map(
    graph.get_edge(graph, from, to) |> result.replace_error(Nil),
  )
  let graph_without_edge = graph.remove_edge(graph, edge_to_reverse)
  let reversed_edge = reverse_edge(edge_to_reverse)

  let assert Ok(final_graph) =
    graph.try_insert_edge(graph_without_edge, reversed_edge)
  final_graph
}
