import aonyx/graph
import aonyx/graph/node
import gleam/list
import gleam/set
import gleam/string
import graph_utils

// We add an Int to the key of the nodes
// this Int is the index of the layer. 0 is bottom.
pub fn minimize_number_of_layers(
  graph: graph.Graph(key, value, label),
) -> graph.Graph(key, #(value, Int), label) {
  let sources =
    graph_utils.get_sources(graph)
    |> list.map(fn(source_vertex) { #(source_vertex, 0) })
  let graph_with_new_vertices_but_no_edges =
    minimize_number_of_layers_recurse(sources, set.new(), graph)
    |> set.fold(graph.new(), fn(current_graph, current_vertex) {
      graph.insert_node(current_graph, current_vertex)
    })
  list.fold(
    graph.get_edges(graph),
    graph_with_new_vertices_but_no_edges,
    fn(current_graph, current_edge) {
      let assert Ok(next_graph) =
        graph.try_insert_edge(current_graph, current_edge)
      next_graph
    },
  )
}

fn minimize_number_of_layers_recurse(
  current_remaining_work: List(#(node.Node(key, value), Int)),
  current_layered_vertices: set.Set(node.Node(key, #(value, Int))),
  graph: graph.Graph(key, value, label),
) -> set.Set(node.Node(key, #(value, Int))) {
  case current_remaining_work {
    [current_work, ..other_remaining_work] -> {
      let #(current_vertex, current_layer) = current_work
      let next_layer = current_layer + 1
      let current_layered_vertex =
        to_layered_vertex(current_vertex, current_layer)
      let targets =
        current_vertex.outgoing
        |> set.to_list
        |> list.map(fn(key) {
          let assert Ok(node) = graph.get_node(graph, key)
            as {
              "Node "
              <> string.inspect(current_vertex.key)
              <> " has an outgoing edge pointing to "
              <> string.inspect(key)
              <> " which was not found in the graph"
            }
          node
        })
      let next_remaining_vertices =
        list.filter(other_remaining_work, fn(future_work) {
          !list.contains(targets, future_work.0)
        })
        |> list.append(
          targets |> list.map(fn(target) { #(target, next_layer) }),
        )
      let next_layered_vertices =
        set.insert(current_layered_vertices, current_layered_vertex)
      minimize_number_of_layers_recurse(
        next_remaining_vertices,
        next_layered_vertices,
        graph,
      )
    }
    [] -> current_layered_vertices
  }
}

fn to_layered_vertex(
  current_vertex: node.Node(key, value),
  current_layer: Int,
) -> node.Node(key, #(value, Int)) {
  node.Node(
    current_vertex.key,
    #(current_vertex.value, current_layer),
    current_vertex.outgoing,
    current_vertex.incoming,
  )
}
