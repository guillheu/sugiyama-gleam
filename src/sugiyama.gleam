import aonyx/graph
import aonyx/graph/node
import break_cycle
import control_points
import coordinates
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import layering
import minimize_crossings

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

pub type VertexType(key) =
  minimize_crossings.VertexType(key)

/// Lay out `graph` with the Sugiyama method.
///
/// The classic phases are applied in order:
///
/// 1. break cycles so the graph becomes a DAG (`break_cycle.berger_shor`),
/// 2. assign every vertex to a layer (`layering.minimize_number_of_layers`),
/// 3. order vertices within each layer to reduce crossings, splitting long
///    edges with virtual vertices (`minimize_crossings.minimize`),
/// 4. turn those in-layer orderings into x-coordinates that align neighbors
///    and straighten edges (`coordinates.straighten`),
/// 5. collapse the virtual-vertex chains back into edges, attaching each
///    chain's coordinates to the edge as curve waypoints (`control_points.route`).
///
/// Every vertex in the returned graph carries a `#(value, layer, x)` triple:
/// `layer` is its row (0 at the top) and `x` its horizontal coordinate. The
/// scaffolding `Virtual` vertices are gone; instead each edge's label is
/// `#(original_label, waypoints)`, where `waypoints` is the ordered list of
/// `#(x, y)` points (source -> target, `y` being the layer index) that a
/// long edge was routed through. Short edges carry an empty list.
pub fn run(
  graph: graph.Graph(key, value, label),
) -> graph.Graph(
  key,
  #(value, Int, Int),
  #(option.Option(label), List(#(Int, Int))),
) {
  graph
  |> break_cycle.berger_shor
  |> layering.minimize_number_of_layers
  |> minimize_crossings.minimize
  |> coordinates.straighten
  |> control_points.route
}
