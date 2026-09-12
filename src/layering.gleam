import aonyx/graph
import aonyx/graph/node
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import graph_utils

// We add an Int to the key of the nodes
// this Int is the index of the layer. 0 is the top.
//
// A vertex goes one layer below the *lowest* of its predecessors, so the
// layering uses as few layers as possible while every edge still points
// downwards. `graph` must already be a DAG — run `break_cycle` on it first,
// or the search below will not terminate.
pub fn minimize_number_of_layers(
  graph: graph.Graph(key, value, label),
) -> graph.Graph(key, #(value, Int), label) {
  let sources =
    graph_utils.get_sources(graph)
    |> list.map(fn(source_vertex) { #(source_vertex, 0) })
  let layers = assign_layers(sources, dict.new(), graph)
  let graph_with_new_vertices_but_no_edges =
    graph.get_nodes(graph)
    |> list.fold(graph.new(), fn(current_graph, current_vertex) {
      let layer = result.unwrap(dict.get(layers, current_vertex.key), 0)
      graph.insert_node(current_graph, to_layered_vertex(current_vertex, layer))
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

// Walk forward from the sources, recording the deepest layer found for each
// vertex. Reaching a vertex by a path no longer than its recorded one tells
// us nothing new, so we stop there; otherwise we push it down and revisit its
// successors. A vertex's layer only ever increases and is bounded by the
// longest path in the graph, so on a DAG this settles.
fn assign_layers(
  current_remaining_work: List(#(node.Node(key, value), Int)),
  current_layers: dict.Dict(key, Int),
  graph: graph.Graph(key, value, label),
) -> dict.Dict(key, Int) {
  case current_remaining_work {
    [current_work, ..other_remaining_work] -> {
      let #(current_vertex, current_layer) = current_work
      case dict.get(current_layers, current_vertex.key) {
        Ok(known_layer) if known_layer >= current_layer ->
          assign_layers(other_remaining_work, current_layers, graph)
        _ -> {
          let next_layer = current_layer + 1
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
              #(node, next_layer)
            })
          assign_layers(
            list.append(other_remaining_work, targets),
            dict.insert(current_layers, current_vertex.key, current_layer),
            graph,
          )
        }
      }
    }
    [] -> current_layers
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
