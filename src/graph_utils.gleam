import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string

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

pub fn transitions_from_node(
  in: graph.Graph(key, value, label),
  from: node.Node(key, value),
) -> List(node.Node(key, value)) {
  graph.get_edges(in)
  |> list.filter_map(fn(edge) {
    case edge.from == from.key {
      True -> graph.get_node(in, edge.to) |> result.replace_error(Nil)
      False -> Error(Nil)
    }
  })
}

pub fn get_incoming_edges(
  vertex: node.Node(key, value),
  edges: List(edge.Edge(key, label)),
) -> List(edge.Edge(key, label)) {
  list.filter(edges, fn(edge) { edge.to == vertex.key })
}

pub fn get_outgoing_edges(
  vertex: node.Node(key, value),
  edges: List(edge.Edge(key, label)),
) -> List(edge.Edge(key, label)) {
  list.filter(edges, fn(edge) { edge.from == vertex.key })
}

pub fn to_string(graph: graph.Graph(key, value, label)) -> String {
  let vertices = graph.get_nodes(graph)
  let edges = graph.get_edges(graph)
  let #(edges_string, lone_vertices) =
    list.fold(edges, #("", vertices), fn(acc, current_edge) {
      let #(current_string, current_lone_vertices) = acc
      let assert Ok(from_vertex) = graph.get_node(graph, current_edge.from)
      let assert Ok(to_vertex) = graph.get_node(graph, current_edge.to)

      let append_to_string =
        "\n"
        <> string.inspect(current_edge.from)
        <> " == "
        <> string.inspect(current_edge.label)
        <> " => "
        <> string.inspect(current_edge.to)
        <> "\n"
        <> string.inspect(from_vertex.value)
        <> "\t"
        <> string.inspect(to_vertex.value)
      let next_lone_vertices =
        list.filter(current_lone_vertices, fn(lone_vertex) {
          current_edge.from == lone_vertex.key
          || current_edge.to == lone_vertex.key
        })
      #(current_string <> append_to_string, next_lone_vertices)
    })
  let lone_vertices_string =
    list.fold(lone_vertices, "", fn(lone_vertices_string, current_lone_vertex) {
      lone_vertices_string
      <> "\n"
      <> string.inspect(current_lone_vertex.key)
      <> "\n"
    })

  edges_string <> lone_vertices_string
}

pub fn get_sources(
  graph: graph.Graph(key, value, label),
) -> List(node.Node(key, value)) {
  graph.get_nodes(graph)
  |> list.filter(fn(vertex) { vertex.incoming |> set.is_empty })
}
