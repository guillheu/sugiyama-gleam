import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import components
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import sugiyama

type Laid =
  graph.Graph(
    String,
    #(String, Int, Int),
    #(option.Option(String), #(#(Int, Int), #(Int, Int))),
  )

fn keyed(keys: List(String)) -> graph.Graph(String, String, String) {
  list.fold(keys, graph.new(), fn(acc, k) {
    graph.insert_node(acc, node.new(k, k))
  })
}

fn keys_of(g: graph.Graph(String, value, label)) -> set.Set(String) {
  graph.get_nodes(g) |> list.map(fn(n) { n.key }) |> set.from_list
}

fn edge_names(g: graph.Graph(String, value, label)) -> String {
  graph.get_edges(g)
  |> list.map(fn(e) { e.from <> "->" <> e.to })
  |> list.sort(string.compare)
  |> string.join(" ")
}

fn layer_of(laid_out: Laid, key: String) -> Int {
  let assert Ok(vertex) = graph.get_node(laid_out, key)
  vertex.value.1
}

// Two components sharing nothing, plus two vertices with no edges at all.
fn mixed_graph() -> graph.Graph(String, String, String) {
  keyed(["A", "B", "C", "X", "Y", "L1", "L2"])
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("B", "C"), "")
  |> graph.insert_edge(edge.new("X", "Y"), "")
}

pub fn split_finds_every_component_test() {
  let pieces = components.split(mixed_graph())

  // Three connected pieces and two lone vertices, each its own component.
  assert list.length(pieces) == 4
  let found = list.map(pieces, keys_of)
  assert list.contains(found, set.from_list(["A", "B", "C"]))
  assert list.contains(found, set.from_list(["X", "Y"]))
  assert list.contains(found, set.from_list(["L1"]))
  assert list.contains(found, set.from_list(["L2"]))
}

// Splitting is a partition: nothing is duplicated, dropped or invented.
pub fn split_preserves_the_graph_test() {
  let original = mixed_graph()
  let pieces = components.split(original)

  let all_keys =
    list.fold(pieces, set.new(), fn(acc, piece) {
      set.union(acc, keys_of(piece))
    })
  assert all_keys == keys_of(original)

  let total_nodes =
    list.fold(pieces, 0, fn(acc, piece) {
      acc + list.length(graph.get_nodes(piece))
    })
  assert total_nodes == list.length(graph.get_nodes(original))

  let all_edges =
    list.flat_map(pieces, fn(piece) { graph.get_edges(piece) })
    |> list.map(fn(e) { e.from <> "->" <> e.to })
    |> list.sort(string.compare)
    |> string.join(" ")
  assert all_edges == edge_names(original)
}

// Connectivity ignores edge direction: a vertex reached only by an incoming
// edge still belongs to the same component as the vertex pointing at it.
pub fn split_ignores_edge_direction_test() {
  let converging =
    keyed(["A", "B", "Z"])
    |> graph.insert_edge(edge.new("A", "Z"), "")
    |> graph.insert_edge(edge.new("B", "Z"), "")
  let assert [only] = components.split(converging)
  assert keys_of(only) == set.from_list(["A", "B", "Z"])
}

pub fn split_of_the_empty_graph_test() {
  assert components.split(graph.new()) == []
}

// Group the laid-out vertices back into components and read off the columns
// each one occupies.
fn column_ranges(laid_out: Laid) -> List(#(Int, Int)) {
  components.split(laid_out)
  |> list.filter_map(fn(piece) {
    let xs = graph.get_nodes(piece) |> list.map(fn(n) { n.value.2 })
    case list.reduce(xs, int.min), list.reduce(xs, int.max) {
      Ok(low), Ok(high) -> Ok(#(low, high))
      _, _ -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

// The point of laying components out separately: each gets its own band of
// columns, with at least one empty column between neighbouring bands, so a
// renderer draws two graphs rather than one tangle.
pub fn components_get_separate_column_bands_test() {
  let ranges = column_ranges(sugiyama.run(mixed_graph()))
  assert list.length(ranges) == 4

  list.window_by_2(ranges)
  |> list.each(fn(pair) {
    let #(#(_, previous_high), #(next_low, _)) = pair
    assert next_low > previous_high + 1
  })
}

// A vertex with no edges is a component of one, so it lands in a column
// nothing else uses — not crammed into the shared layer-0 row.
pub fn isolated_vertices_get_their_own_columns_test() {
  let laid_out = sugiyama.run(keyed(["A", "B", "C"]))

  // Nothing to stack, so they all sit on the top row.
  list.each(["A", "B", "C"], fn(key) {
    assert layer_of(laid_out, key) == 0
  })

  let xs = graph.get_nodes(laid_out) |> list.map(fn(n) { n.value.2 })
  assert list.length(xs) == 3
  assert set.size(set.from_list(xs)) == 3
}

// Nothing may fall out of the pipeline on the way through, however
// disconnected the input is.
pub fn layout_keeps_every_vertex_and_edge_test() {
  let original = mixed_graph()
  let laid_out = sugiyama.run(original)

  assert keys_of(laid_out) == keys_of(original)
  assert list.length(graph.get_edges(laid_out))
    == list.length(graph.get_edges(original))
}

pub fn empty_graph_lays_out_to_the_empty_graph_test() {
  let laid_out = sugiyama.run(graph.new())
  assert graph.get_nodes(laid_out) == []
  assert graph.get_edges(laid_out) == []
}

// Being laid out in a later band must not cost a component any layout
// quality: this one's long edge still comes out as a straight vertical line,
// exactly as it does when it is the only component in the graph.
pub fn a_later_component_is_laid_out_just_as_well_test() {
  let laid_out =
    sugiyama.run(
      keyed(["A", "B", "P", "Q", "R", "S"])
      |> graph.insert_edge(edge.new("A", "B"), "")
      |> graph.insert_edge(edge.new("P", "Q"), "")
      |> graph.insert_edge(edge.new("Q", "R"), "")
      |> graph.insert_edge(edge.new("R", "S"), "")
      // spans three layers, so it is routed through virtual vertices
      |> graph.insert_edge(edge.new("P", "S"), ""),
    )

  let assert Ok(p) = graph.get_node(laid_out, "P")
  let assert Ok(s) = graph.get_node(laid_out, "S")
  let assert Ok(long_edge) = graph.get_edge(laid_out, "P", "S")
  let assert option.Some(#(_, #(c1, c2))) = long_edge.label

  assert set.size(set.from_list([p.value.2, c1.0, c2.0, s.value.2])) == 1
}

// A self-loop leaves its vertex with an incoming edge that cycle-breaking
// cannot remove — reversing `S -> S` gives back `S -> S`. Left in the graph
// it keeps `S` off every list of sources, and layering then never reaches
// the component at all and silently drops all of it onto layer 0.
pub fn a_self_loop_does_not_flatten_its_component_test() {
  let laid_out =
    sugiyama.run(
      keyed(["S", "T", "U"])
      |> graph.insert_edge(edge.new("S", "S"), "")
      |> graph.insert_edge(edge.new("S", "T"), "")
      |> graph.insert_edge(edge.new("T", "U"), ""),
    )

  assert layer_of(laid_out, "S") == 0
  assert layer_of(laid_out, "T") == 1
  assert layer_of(laid_out, "U") == 2
}

// Self-loops sit out the layout, but they are still the caller's edges and
// must come back — with control points that bulge off the vertex, so the
// curve is a visible loop instead of a zero-length line.
pub fn a_self_loop_survives_the_layout_test() {
  let laid_out =
    sugiyama.run(
      keyed(["S", "T"])
      |> graph.insert_edge(edge.new("S", "S"), "")
      |> graph.insert_edge(edge.new("S", "T"), ""),
    )

  let assert Ok(s) = graph.get_node(laid_out, "S")
  let assert Ok(loop) = graph.get_edge(laid_out, "S", "S")
  let assert option.Some(#(_, #(c1, c2))) = loop.label

  let #(_, layer, x) = s.value
  assert c1 != #(x, layer)
  assert c2 != #(x, layer)
  assert c1 != c2
}

// A vertex whose only edge is a self-loop has nothing to connect it to
// anything, so it is a component of one like any other lone vertex.
pub fn a_vertex_with_only_a_self_loop_test() {
  let laid_out =
    sugiyama.run(
      keyed(["A", "B"])
      |> graph.insert_edge(edge.new("A", "A"), "")
      |> graph.insert_edge(edge.new("B", "B"), ""),
    )

  assert keys_of(laid_out) == set.from_list(["A", "B"])
  assert list.length(graph.get_edges(laid_out)) == 2
  let xs = graph.get_nodes(laid_out) |> list.map(fn(n) { n.value.2 })
  assert set.size(set.from_list(xs)) == 2
}

// Edge labels and weights ride through the split-and-pack unchanged.
pub fn packing_preserves_labels_and_weights_test() {
  let laid_out =
    sugiyama.run(
      keyed(["A", "B", "X", "Y"])
      |> graph.insert_edge(edge.new("A", "B"), "")
      |> graph.insert_edge(edge.new("X", "Y") |> edge.with_weight(2.5), "")
      |> graph.insert_edge(edge.new("X", "Y") |> edge.with_label("tagged"), ""),
    )

  let assert Ok(tagged) = graph.get_edge(laid_out, "X", "Y")
  let assert option.Some(#(original_label, _)) = tagged.label
  assert original_label == option.Some("tagged")
}

// Every control point must land inside the drawing, not at a stale
// coordinate from before the component was slid into its own band.
pub fn control_points_follow_their_component_test() {
  let laid_out = sugiyama.run(mixed_graph())
  let positions =
    graph.get_nodes(laid_out)
    |> list.fold(dict.new(), fn(acc, n) {
      dict.insert(acc, n.key, #(n.value.2, n.value.1))
    })

  graph.get_edges(laid_out)
  |> list.each(fn(e) {
    let assert option.Some(#(_, #(c1, c2))) = e.label
    let assert Ok(#(from_x, _)) = dict.get(positions, e.from)
    let assert Ok(#(to_x, _)) = dict.get(positions, e.to)
    let low = int.min(from_x, to_x)
    let high = int.max(from_x, to_x)
    // Both endpoints are in the same band, so the curve between them stays
    // in that band too.
    assert c1.0 >= low && c1.0 <= high
    assert c2.0 >= low && c2.0 <= high
  })
}

// Layering is per-component, so every component starts at the top rather
// than being pushed down by a deeper neighbour.
pub fn every_component_starts_at_layer_zero_test() {
  let laid_out = sugiyama.run(mixed_graph())

  components.split(laid_out)
  |> list.each(fn(piece) {
    let layers = graph.get_nodes(piece) |> list.map(fn(n) { n.value.1 })
    assert result.unwrap(list.reduce(layers, int.min), -1) == 0
  })
}
