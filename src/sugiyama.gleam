import aonyx/graph
import break_cycle
import components
import control_points
import coordinates
import gleam/list
import gleam/option
import graph_utils
import layering
import minimize_crossings

pub type VertexType(key) =
  minimize_crossings.VertexType(key)

/// Lay out `graph` with the Sugiyama method.
///
/// The classic phases are applied in order:
///
/// 1. set aside the self-loops, which no layered drawing can route
///    (`graph_utils.partition_self_loops`),
/// 2. break cycles so the graph becomes a DAG (`break_cycle.eades_lin_smyth`),
/// 3. cut the graph into its connected components (`components.split`), and
///    lay each out on its own:
///    - assign every vertex to a layer (`layering.minimize_number_of_layers`),
///    - order vertices within each layer to reduce crossings, splitting long
///      edges with virtual vertices (`minimize_crossings.minimize`),
///    - turn those in-layer orderings into x-coordinates that align neighbors
///      and straighten edges (`coordinates.straighten`),
/// 4. slide the components into non-overlapping horizontal bands and merge
///    them back into one graph (`components.pack`),
/// 5. collapse the virtual-vertex chains back into edges, condensing each
///    chain's coordinates into two curve control points (`control_points.route`),
/// 6. reattach the self-loops (`control_points.add_self_loops`).
///
/// Every vertex in the returned graph carries a `#(value, layer, x)` triple:
/// `layer` is its row (0 at the top) and `x` its horizontal coordinate. The
/// scaffolding `Virtual` vertices are gone; instead each edge's label is
/// `#(original_label, #(c1, c2))`, the two control points of a cubic curve
/// running from the source vertex to the target one. Each is an `#(x, y)`
/// point, `y` being the layer index. For a long edge they are the first and
/// last vertex of the chain it was routed through; for a short edge they sit
/// a third and two thirds of the way along the straight line between its
/// endpoints, so it renders as a straight edge.
///
/// Disconnected input is fine. Each connected component is laid out
/// independently and the results are placed side by side, so no two
/// components share a column and every component starts at layer 0. A
/// vertex with no edges is a component of one and gets a column to itself.
/// The empty graph lays out to the empty graph.
pub fn run(
  graph: graph.Graph(key, value, label),
) -> graph.Graph(
  key,
  #(value, Int, Int),
  #(option.Option(label), #(#(Int, Int), #(Int, Int))),
) {
  let #(self_loops, graph) = graph_utils.partition_self_loops(graph)

  graph
  |> break_cycle.eades_lin_smyth
  |> components.split
  |> list.map(fn(component) {
    component
    |> layering.minimize_number_of_layers
    |> minimize_crossings.minimize
    |> coordinates.straighten
  })
  |> components.pack
  |> control_points.route
  |> control_points.add_self_loops(self_loops)
}
