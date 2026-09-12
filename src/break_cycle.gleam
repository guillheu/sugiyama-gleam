import aonyx/graph.{type Graph}
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/set
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
      // Keep whichever side is larger and flip the other, so we reverse as
      // few edges as possible. Either choice leaves the vertex a pure source
      // or a pure sink among the edges still in play, which is what makes
      // the result acyclic; keeping the larger side is what makes it good.
      let next_edges_to_flip = case
        int.compare(list.length(incoming_edges), list.length(outgoing_edges))
      {
        // At least as many outgoing as incoming: keep the outgoing edges,
        // flip the incoming ones, and the vertex becomes a source.
        order.Lt | order.Eq -> list.append(edges_to_flip, incoming_edges)
        // More incoming than outgoing: keep the incoming edges, flip the
        // outgoing ones, and the vertex becomes a sink.
        order.Gt -> list.append(edges_to_flip, outgoing_edges)
      }
      let next_remaining_edges =
        remaining_edges
        |> list.filter(fn(edge) { !list.contains(outgoing_edges, edge) })
        |> list.filter(fn(edge) { !list.contains(incoming_edges, edge) })
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

/// Order the vertices left to right, then reverse every edge that points
/// backwards in that order. The result is a DAG, because "every edge points
/// forwards in some fixed vertex order" is exactly what acyclic means.
///
/// The order is built from both ends. Sinks are peeled off the right and
/// sources off the left; an edge touching one of those cannot end up pointing
/// backwards, so it survives untouched. Only when what remains has neither —
/// which means it still holds a cycle — do we force a vertex out, picking the
/// one with the largest excess of outgoing over incoming edges, and accept
/// that its remaining incoming edges get reversed.
///
/// An acyclic graph always has a sink and a source, so it never reaches that
/// last case and passes through completely unchanged. That is the property
/// `berger_shor` lacks and the reason to prefer this: layering reads edge
/// directions as the hierarchy to draw, so reversing edges of a graph that
/// was already fine silently inverts parts of the drawing.
pub fn eades_lin_smyth(
  g: Graph(key, value, label),
) -> Graph(key, value, label) {
  let remaining =
    graph.get_nodes(g)
    |> list.fold(dict.new(), fn(acc, vertex) {
      dict.insert(acc, vertex.key, #(vertex.incoming, vertex.outgoing))
    })
  let #(left, right) = greedy_order(remaining, [], [])
  let position =
    list.append(list.reverse(left), right)
    |> list.index_fold(dict.new(), fn(acc, key, index) {
      dict.insert(acc, key, index)
    })

  let #(edges_to_keep, edges_to_flip) =
    graph.get_edges(g)
    |> list.partition(fn(current_edge) {
      let assert Ok(from_position) = dict.get(position, current_edge.from)
      let assert Ok(to_position) = dict.get(position, current_edge.to)
      from_position < to_position
    })

  let all_edges =
    list.append(
      edges_to_keep,
      list.map(edges_to_flip, graph_utils.reverse_edge),
    )
  let graph_only_vertices = list.fold(graph.get_edges(g), g, graph.remove_edge)
  list.fold(all_edges, graph_only_vertices, fn(current_graph, edge_to_insert) {
    let assert Ok(next_graph) =
      graph.try_insert_edge(current_graph, edge_to_insert)
    next_graph
  })
}

type Remaining(key) =
  dict.Dict(key, #(set.Set(key), set.Set(key)))

// `left` is accumulated head-first and reversed at the end. `right` is also
// accumulated head-first but needs no reversing: each sink we find belongs in
// front of the ones found before it.
fn greedy_order(
  remaining: Remaining(key),
  left: List(key),
  right: List(key),
) -> #(List(key), List(key)) {
  case pick(remaining, fn(degrees) { set.is_empty(degrees.1) }) {
    // A sink: nothing it points at is left, so it goes as far right as it can.
    Ok(sink) ->
      greedy_order(remove_vertex(remaining, sink), left, [sink, ..right])
    Error(Nil) ->
      case pick(remaining, fn(degrees) { set.is_empty(degrees.0) }) {
        // A source: nothing points at it, so it goes as far left as it can.
        Ok(source) ->
          greedy_order(
            remove_vertex(remaining, source),
            [source, ..left],
            right,
          )
        Error(Nil) ->
          case pick_largest_excess(remaining) {
            // Everything left is tangled in cycles, so some edge has to give.
            // Taking the vertex that points outwards the most gives up the
            // fewest.
            Ok(vertex) ->
              greedy_order(
                remove_vertex(remaining, vertex),
                [vertex, ..left],
                right,
              )
            Error(Nil) -> #(left, right)
          }
      }
  }
}

fn pick(
  remaining: Remaining(key),
  is_match: fn(#(set.Set(key), set.Set(key))) -> Bool,
) -> Result(key, Nil) {
  dict.to_list(remaining)
  |> list.find(fn(entry) { is_match(entry.1) })
  |> result.map(fn(entry) { entry.0 })
}

fn pick_largest_excess(remaining: Remaining(key)) -> Result(key, Nil) {
  dict.to_list(remaining)
  |> list.reduce(fn(best, entry) {
    case excess(entry.1) > excess(best.1) {
      True -> entry
      False -> best
    }
  })
  |> result.map(fn(entry) { entry.0 })
}

fn excess(degrees: #(set.Set(key), set.Set(key))) -> Int {
  set.size(degrees.1) - set.size(degrees.0)
}

// Drop a vertex and unlink it from the neighbours it leaves behind, so their
// degrees stay accurate for the next round.
fn remove_vertex(remaining: Remaining(key), key: key) -> Remaining(key) {
  let assert Ok(#(incoming, outgoing)) = dict.get(remaining, key)
  let without = dict.delete(remaining, key)
  let without =
    set.fold(incoming, without, fn(acc, from) {
      case dict.get(acc, from) {
        Ok(#(from_incoming, from_outgoing)) ->
          dict.insert(acc, from, #(
            from_incoming,
            set.delete(from_outgoing, key),
          ))
        Error(Nil) -> acc
      }
    })
  set.fold(outgoing, without, fn(acc, to) {
    case dict.get(acc, to) {
      Ok(#(to_incoming, to_outgoing)) ->
        dict.insert(acc, to, #(set.delete(to_incoming, key), to_outgoing))
      Error(Nil) -> acc
    }
  })
}
