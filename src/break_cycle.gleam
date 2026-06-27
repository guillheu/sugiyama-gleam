import aonyx/graph.{type Graph}
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order
import graph_utils

// Cut either incoming or outgoing edges from every vertex, whichever is fewest.
pub fn berger_shor(g: Graph(key, value, label)) -> Graph(key, value, label) {
  //1.1: initialize empty set of edges E' (accumulator)
  let edges = graph.get_edges(g)
  let vertices = graph.get_nodes(g)
  //2 loop through all vertices (pass E1 and full graph to the loop)
  let edges_to_flip = recurse_berger_shor(vertices, edges, [])
  //3: return the set of all vertices and E'
  let flipped_edges = list.map(edges_to_flip, graph_utils.reverse_edge)
  let edges_to_keep =
    list.fold(edges_to_flip, g, graph.remove_edge)
    |> graph.get_edges
  let all_edges = list.append(edges_to_keep, flipped_edges)

  //4: G = (V, E') is a DAG
  // E \ E' is the "feedback set" (edges to be inverted)
  let graph_only_vertices = list.fold(edges, g, graph.remove_edge)
  list.fold(all_edges, graph_only_vertices, fn(edge_to_insert, graph) {
    let assert Ok(graph) = graph.try_insert_edge(edge_to_insert, graph)
    graph
  })
}

// This function returns edges to be flipped
fn recurse_berger_shor(
  remaining_vertices: List(node.Node(key, value)),
  remaining_edges: List(edge.Edge(key, label)),
  edges_to_flip: List(edge.Edge(key, label)),
) -> List(edge.Edge(key, label)) {
  case remaining_vertices {
    [current_vertex, ..next_remaining_vertices] -> {
      let incoming_edges =
        graph_utils.get_incoming_edges(current_vertex, remaining_edges)
      let outgoing_edges =
        graph_utils.get_outgoing_edges(current_vertex, remaining_edges)
      let next_edges_to_flip = case
        int.compare(list.length(incoming_edges), list.length(outgoing_edges))
      {
        // More outgoing edges than incoming edges (or equal)
        order.Lt | order.Eq -> list.append(edges_to_flip, outgoing_edges)
        // more incoming edges thanoutgoing edges
        order.Gt -> list.append(edges_to_flip, incoming_edges)
      }
      let next_remaining_edges =
        remaining_edges
        |> list.filter(list.contains(outgoing_edges, _))
        |> list.filter(list.contains(incoming_edges, _))
      recurse_berger_shor(
        next_remaining_vertices,
        next_remaining_edges,
        next_edges_to_flip,
      )
    }
    [] -> edges_to_flip
  }
  //2.1 if the outgoing edges of v outnumber incoming edges of v, add outgoing edges to E'
  //2.2 otherwise, add incoming edges to the E' set
  //2.3 remove v and v's edges from the graph
  // /!\ IMPORTANT /!\ Once an edge is removed by an iteration it cannot show up in another iteration (for the other vertex it's connected to)
}
// pub fn eades_lin_smyth(g: yog.Graph(a, b)) -> Nil {
//   todo
//   //  1 Initialize E' to an empty set of edges
//   //  2 While there are vertices remaining
//   //    2.1 Iterate through all the sinks (vertices with only incoming edges)
//   //      2.1.1 add all the edges of the sink v to E'
//   //      2.1.2 remove v and its edges from G
//   //        /!\ IMPORTANT /!\ step 2.2 may create new sinks
//   //    2.2 remove all isolated vertices
//   //    2.3 repeat step 2.1 with sources rather than sinks
//   //    2.4 If there are vertices remaining
//   //      2.4.1 select the vertex with the most outgoing edges compared to incoming edges
//   //      2.4.2 add its outgoing edges to E'
//   //      2.4.3 remove the incoming edges and the vertex
//   //  3 Reverse E \ E'
// }
