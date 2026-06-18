import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/list
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

pub fn has_cycles(graph: graph.Graph(key, value, label)) {
  has_cycles_recurse(graph.get_nodes(graph), graph, [])
}

fn has_cycles_recurse(eval_next, graph, checked_nodes) -> Bool {
  case eval_next {
    [first, ..rest] -> {
      let cycle_detected =
        transitions_from_node(graph, first)
        |> list.any(fn(next_node) { list.contains(checked_nodes, next_node) })
      case cycle_detected, rest {
        True, _ -> True
        False, [] -> False
        False, rest -> has_cycles_recurse(rest, graph, [first, ..checked_nodes])
      }
    }
    [] -> False
  }
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
