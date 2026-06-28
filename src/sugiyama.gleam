import aonyx/graph
import aonyx/graph/node
import gleam/list
import gleam/result
import gleam/set

pub fn apply(
  graph: graph.Graph(key, value, label),
  max_columns: Int,
) -> graph.Graph(key, #(value, Int, Int), label) {
  assert max_columns > 0 as "max_columns should be a positive integer"
  let vertices = graph.get_nodes(graph)
  let edges = graph.get_edges(graph)
  let new_vertices =
    list.index_map(vertices, fn(vertex, index) {
      node.Node(
        key: vertex.key,
        value: #(vertex.value, index % max_columns, index / max_columns),
        outgoing: set.new(),
        incoming: set.new(),
      )
    })
  let graph_without_edges =
    list.fold(new_vertices, graph.new(), fn(graph, vertex) {
      graph.insert_node(graph, vertex)
    })
  list.fold(edges, graph_without_edges, fn(graph, edge) {
    graph.try_insert_edge(graph, edge)
    |> result.lazy_unwrap(fn() { panic as "missing node" })
  })
}
