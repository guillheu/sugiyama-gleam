import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/list
import gleam/option
import graph_utils

type VertexType(key) {
  Real(inner: key)
  Virtual(from: key, to: key, index: Int)
}

pub fn minimize(
  graph: graph.Graph(key, #(value, Int), label),
) -> graph.Graph(key, #(value, Int, Int), label) {
  // 1: add dummy nodes for edges that jump more than 1 layer
  let graph_with_virtual_vertices =
    graph.get_edges(graph)
    |> list.fold(graph.new(), fn(current_graph, current_edge) {
      let assert Ok(from_vertex) = graph.get_node(graph, current_edge.from)
      edge_to_dummy_vertices(
        current_graph,
        current_edge,
        from_vertex.value.0,
        graph,
      )
    })
    |> graph_utils.to_string
  todo
}

fn edge_to_dummy_vertices(
  graph: graph.Graph(VertexType(key), #(value, Int), label),
  edge: edge.Edge(key, label),
  default_value: value,
  reference_graph: graph.Graph(key, #(value, Int), label),
) -> graph.Graph(VertexType(key), #(value, Int), label) {
  let assert Ok(from) = graph.get_node(reference_graph, edge.from)
  let assert Ok(to) = graph.get_node(reference_graph, edge.to)
  let from_layer = from.value.1
  let to_layer = to.value.1
  assert from_layer < to_layer
    as "edges should always go strictly upwards, never down or horizontally"
  let virtual_vertices =
    list.repeat(Nil, to_layer - from_layer - 1)
    |> list.index_map(fn(_, index) {
      let current_vertex_layer = index + from_layer + 1
      node.new(
        Virtual(from: from.key, to: to.key, index: current_vertex_layer),
        #(default_value, current_vertex_layer),
      )
    })
  let virtual_edges =
    list.window_by_2(virtual_vertices)
    |> list.map(fn(virtual_pair) {
      let #(from_virtual, to_virtual) = virtual_pair
      edge.Edge(from_virtual.key, to_virtual.key, edge.label, edge.weight)
    })

  let new_graph_with_nodes =
    list.fold(virtual_vertices, graph, fn(graph, virtual_vertex) {
      graph.insert_node(graph, virtual_vertex)
    })
  list.fold(
    virtual_edges,
    new_graph_with_nodes,
    fn(current_graph, virtual_edge) {
      let assert Ok(next_graph) =
        graph.try_insert_edge(current_graph, virtual_edge)
      next_graph
    },
  )
}
