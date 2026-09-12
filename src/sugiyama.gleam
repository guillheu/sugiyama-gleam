import aonyx/graph
import break_cycle
import control_points
import coordinates
import gleam/option
import layering
import minimize_crossings

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
/// 5. collapse the virtual-vertex chains back into edges, condensing each
///    chain's coordinates into two curve control points (`control_points.route`).
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
pub fn run(
  graph: graph.Graph(key, value, label),
) -> graph.Graph(
  key,
  #(value, Int, Int),
  #(option.Option(label), #(#(Int, Int), #(Int, Int))),
) {
  graph
  |> break_cycle.eades_lin_smyth
  |> layering.minimize_number_of_layers
  |> minimize_crossings.minimize
  |> coordinates.straighten
  |> control_points.route
}
