import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import layering

fn layer_of(
  laid_out: graph.Graph(String, #(String, Int), String),
  key: String,
) {
  let assert Ok(vertex) = graph.get_node(laid_out, key)
  vertex.value.1
}

fn with_nodes(keys: List(String)) -> graph.Graph(String, String, String) {
  list.fold(keys, graph.new(), fn(acc, k) {
    graph.insert_node(acc, node.new(k, k))
  })
}

// A vertex must end up below the *lowest* of its predecessors, not the
// first one that happens to reach it. Here A -> Z is a shortcut past the
// four-hop path A -> B -> C -> D -> Z, so Z belongs in layer 4.
pub fn longest_path_wins_test() {
  let laid_out =
    with_nodes(["A", "B", "C", "D", "Z"])
    |> graph.insert_edge(edge.new("A", "Z"), "")
    |> graph.insert_edge(edge.new("A", "B"), "")
    |> graph.insert_edge(edge.new("B", "C"), "")
    |> graph.insert_edge(edge.new("C", "D"), "")
    |> graph.insert_edge(edge.new("D", "Z"), "")
    |> layering.minimize_number_of_layers

  assert layer_of(laid_out, "A") == 0
  assert layer_of(laid_out, "B") == 1
  assert layer_of(laid_out, "C") == 2
  assert layer_of(laid_out, "D") == 3
  assert layer_of(laid_out, "Z") == 4
}

// A chain of asymmetric diamonds: from every `a` a short hop straight to the
// next `a`, plus a two-hop detour through `b` and `c`. The detour always
// wins, so `a<i>` sits in layer 3i. Cascading pushes like these are what
// break a layering that only records the first layer it finds for a vertex.
pub fn cascading_pushes_test() {
  let size = 8
  let keys =
    int.range(from: 0, to: size + 1, with: [], run: fn(acc, i) {
      let i = int.to_string(i)
      ["a" <> i, "b" <> i, "c" <> i, ..acc]
    })
  let laid_out =
    int.range(from: 0, to: size, with: with_nodes(keys), run: fn(acc, i) {
      let a = "a" <> int.to_string(i)
      let next = "a" <> int.to_string(i + 1)
      acc
      |> graph.insert_edge(edge.new(a, next), "")
      |> graph.insert_edge(edge.new(a, "b" <> int.to_string(i)), "")
      |> graph.insert_edge(
        edge.new("b" <> int.to_string(i), "c" <> int.to_string(i)),
        "",
      )
      |> graph.insert_edge(edge.new("c" <> int.to_string(i), next), "")
    })
    |> layering.minimize_number_of_layers

  int.range(from: 0, to: size + 1, with: Nil, run: fn(_, i) {
    assert layer_of(laid_out, "a" <> int.to_string(i)) == 3 * i
    Nil
  })

  // Every edge points strictly downwards, which is what the later phases
  // rely on to split long edges into virtual-vertex chains.
  graph.get_edges(laid_out)
  |> list.each(fn(e) {
    assert layer_of(laid_out, e.to) > layer_of(laid_out, e.from)
  })
}

// Two components that share no edges are laid out independently, each
// starting from its own source at layer 0.
pub fn disconnected_components_test() {
  let laid_out =
    with_nodes(["A", "B", "X", "Y", "Z"])
    |> graph.insert_edge(edge.new("A", "B"), "")
    |> graph.insert_edge(edge.new("X", "Y"), "")
    |> graph.insert_edge(edge.new("Y", "Z"), "")
    |> layering.minimize_number_of_layers

  assert layer_of(laid_out, "A") == 0
  assert layer_of(laid_out, "B") == 1
  assert layer_of(laid_out, "X") == 0
  assert layer_of(laid_out, "Y") == 1
  assert layer_of(laid_out, "Z") == 2
}

// Layering must not add, drop or merge vertices, and must keep every edge.
pub fn preserves_the_graph_test() {
  let original =
    with_nodes(["A", "B", "C", "D"])
    |> graph.insert_edge(edge.new("A", "B"), "")
    |> graph.insert_edge(edge.new("B", "C"), "")
    |> graph.insert_edge(edge.new("C", "D"), "")
    |> graph.insert_edge(edge.new("A", "D"), "")
  let laid_out = layering.minimize_number_of_layers(original)

  let values =
    graph.get_nodes(laid_out)
    |> list.fold(dict.new(), fn(acc, n) { dict.insert(acc, n.key, n.value.0) })
  assert dict.size(values) == 4
  // The original value rides along untouched beside the layer.
  assert result.unwrap(dict.get(values, "C"), "") == "C"

  assert list.length(graph.get_edges(laid_out))
    == list.length(graph.get_edges(original))
}
