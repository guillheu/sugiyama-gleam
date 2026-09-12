import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import break_cycle
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import sugiyama_test

pub fn break_cycle_test() {
  let start_graph = get_cyclic_graph()
  let graph_no_cycles = break_cycle.berger_shor(start_graph)
  assert !sugiyama_test.has_cycles(graph_no_cycles)
}

pub fn eades_lin_smyth_breaks_cycles_test() {
  let graph_no_cycles = break_cycle.eades_lin_smyth(get_cyclic_graph())
  assert !sugiyama_test.has_cycles(graph_no_cycles)
}

// The property the whole layout depends on: a graph that is already acyclic
// is already a valid hierarchy, so cycle-breaking must not touch a single
// edge. Reversing any of them would flip part of the drawing upside down.
pub fn eades_lin_smyth_leaves_acyclic_graphs_alone_test() {
  list.each([get_acyclic_graph(), diamond_fan(), binary_tree()], fn(original) {
    let broken = break_cycle.eades_lin_smyth(original)
    assert edge_names(broken) == edge_names(original)
  })
}

// Only the edges that actually close a cycle get reversed.
pub fn eades_lin_smyth_reverses_only_the_back_edge_test() {
  let original =
    keyed(["A", "B", "C", "D", "E"])
    |> graph.insert_edge(edge.new("A", "B"), "")
    |> graph.insert_edge(edge.new("B", "C"), "")
    |> graph.insert_edge(edge.new("C", "D"), "")
    |> graph.insert_edge(edge.new("D", "E"), "")
    // the single back edge closing the loop
    |> graph.insert_edge(edge.new("E", "A"), "")
  let broken = break_cycle.eades_lin_smyth(original)

  assert !sugiyama_test.has_cycles(broken)
  let kept = set.intersection(edge_set(broken), edge_set(original)) |> set.size
  assert kept == 4
}

fn edge_set(g: graph.Graph(String, String, String)) -> set.Set(String) {
  graph.get_edges(g)
  |> list.map(fn(e) { e.from <> "->" <> e.to })
  |> set.from_list
}

fn edge_names(g: graph.Graph(String, String, String)) -> String {
  graph.get_edges(g)
  |> list.map(fn(e) { e.from <> "->" <> e.to })
  |> list.sort(string.compare)
  |> string.join(" ")
}

fn keyed(keys: List(String)) -> graph.Graph(String, String, String) {
  list.fold(keys, graph.new(), fn(acc, k) {
    graph.insert_node(acc, node.new(k, k))
  })
}

fn get_acyclic_graph() -> graph.Graph(String, String, String) {
  keyed(["A", "B", "C"])
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("B", "C"), "")
}

fn get_cyclic_graph() -> graph.Graph(String, String, String) {
  get_acyclic_graph()
  |> graph.insert_edge(edge.new("C", "A"), "")
}

fn diamond_fan() -> graph.Graph(String, String, String) {
  keyed(["A", "B", "C", "D", "E", "F"])
  |> graph.insert_edge(edge.new("A", "B"), "")
  |> graph.insert_edge(edge.new("A", "C"), "")
  |> graph.insert_edge(edge.new("B", "D"), "")
  |> graph.insert_edge(edge.new("C", "D"), "")
  |> graph.insert_edge(edge.new("D", "E"), "")
  |> graph.insert_edge(edge.new("E", "F"), "")
}

fn binary_tree() -> graph.Graph(String, String, String) {
  let keys =
    int.range(from: 0, to: 15, with: [], run: fn(acc, i) {
      ["n" <> int.to_string(i), ..acc]
    })
  int.range(from: 1, to: 15, with: keyed(keys), run: fn(acc, i) {
    let parent = "n" <> int.to_string({ i - 1 } / 2)
    graph.insert_edge(acc, edge.new(parent, "n" <> int.to_string(i)), "")
  })
}
