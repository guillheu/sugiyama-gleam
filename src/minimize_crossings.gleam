import aonyx/graph
import aonyx/graph/edge
import aonyx/graph/node
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/set
import graph_utils

pub type VertexType(key) {
  Real(inner: key)
  Virtual(from: key, to: key, index: Int)
}

pub fn minimize(
  graph: graph.Graph(key, #(value, Int), label),
) -> graph.Graph(VertexType(key), #(value, Int, Int), label) {
  // ) {
  // 1: add dummy nodes for edges that jump more than 1 layer
  let #(virtual_vertices, virtual_edges) =
    graph.get_edges(graph)
    |> list.fold(#(set.new(), set.new()), fn(current_graph, current_edge) {
      let assert Ok(from_vertex) = graph.get_node(graph, current_edge.from)
      edge_to_dummy_vertices(
        current_graph,
        current_edge,
        from_vertex.value.0,
        graph,
      )
    })

  // 2. derive a list of layers from the bottom up. Each layer contains a set of nodes and a set of edges.
  let layered_vertices =
    set.fold(virtual_vertices, dict.new(), fn(current_layers, current_vertex) {
      let current_vertex_layer = current_vertex.value.1

      let new_layered_vertices = case
        dict.get(current_layers, current_vertex_layer)
      {
        Ok(layered_vertices) -> set.insert(layered_vertices, current_vertex)
        Error(_) -> set.from_list([current_vertex])
      }

      dict.insert(current_layers, current_vertex_layer, new_layered_vertices)
    })
    |> dict.to_list
    |> list.sort(fn(layer_left, layer_right) {
      int.compare(layer_left.0, layer_right.0)
    })
    |> list.map(fn(layer) { layer.1 |> set.to_list })

  let ordered_layers =
    [[], ..layered_vertices]
    |> iterate_through_layer_pairs([])

  let graph_with_positionned_vertices =
    {
      use layer <- list.map(ordered_layers)
      use vertex, index <- list.index_map(layer)
      node.Node(..vertex, value: #(vertex.value.0, vertex.value.1, index))
    }
    |> list.flatten
    |> list.fold(graph.new(), fn(current_graph, current_vertex) {
      graph.insert_node(current_graph, current_vertex)
    })

  set.fold(
    virtual_edges,
    graph_with_positionned_vertices,
    fn(current_graph, current_edge) {
      let assert Ok(next_graph) =
        graph.try_insert_edge(current_graph, current_edge)
      next_graph
    },
  )
  // when evaluating each layer, compare it to the layer below (the "fixed" layer)
  // This means evaluating the first layer against an empty layer.

  //   |> graph_utils.to_string
  //   |> io.println
  //   todo
}

fn iterate_through_layer_pairs(
  current_layers: List(List(node.Node(VertexType(key), #(value, Int)))),
  accumulator: List(List(node.Node(VertexType(key), #(value, Int)))),
) -> List(List(node.Node(VertexType(key), #(value, Int)))) {
  case current_layers {
    [fixed_layer, current_layer, ..rest] -> {
      let current_layer_ordered = order_layer_pair(fixed_layer, current_layer)
      let next_accumulator = [current_layer_ordered, ..accumulator]
      iterate_through_layer_pairs(
        [current_layer_ordered, ..rest],
        next_accumulator,
      )
    }
    [_] -> accumulator
    [] ->
      panic as "there should never be a case with no layers remaining - when we reach 1 layer the recursion should end"
  }
}

fn order_layer_pair(
  fixed_layer: List(node.Node(VertexType(key), #(value, Int))),
  current_layer: List(node.Node(VertexType(key), #(value, Int))),
) -> List(node.Node(VertexType(key), #(value, Int))) {
  todo
}

fn edge_to_dummy_vertices(
  current_nodes_and_edges: #(
    set.Set(node.Node(VertexType(key), #(value, Int))),
    set.Set(edge.Edge(VertexType(key), label)),
  ),
  edge: edge.Edge(key, label),
  default_value: value,
  reference_graph: graph.Graph(key, #(value, Int), label),
) -> #(
  set.Set(node.Node(VertexType(key), #(value, Int))),
  set.Set(edge.Edge(VertexType(key), label)),
) {
  let #(current_nodes, current_edges) = current_nodes_and_edges
  let assert Ok(from) = graph.get_node(reference_graph, edge.from)
  let assert Ok(to) = graph.get_node(reference_graph, edge.to)
  let from_layer = from.value.1
  let to_layer = to.value.1
  assert from_layer < to_layer
    as "edges should always go strictly upwards, never down or horizontally"
  let virtual_vertices =
    list.repeat(Nil, to_layer - from_layer - 1)
    |> list.index_map(fn(_, index) {
      let current_vertex_layer = index + from_layer + 1
      node.new(
        Virtual(from: from.key, to: to.key, index: current_vertex_layer),
        #(default_value, current_vertex_layer),
      )
    })

  let split_edges =
    list.append(
      [
        node.Node(Real(from.key), from.value, set.new(), set.new()),
        ..virtual_vertices
      ],
      [node.Node(Real(to.key), to.value, set.new(), set.new())],
    )
    |> list.window_by_2
    |> list.map(fn(virtual_pair) {
      let #(from_virtual, to_virtual) = virtual_pair
      edge.Edge(from_virtual.key, to_virtual.key, edge.label, edge.weight)
    })

  let new_nodes =
    virtual_vertices
    |> set.from_list
    |> set.insert(node.new(Real(from.key), from.value))
    |> set.insert(node.new(Real(to.key), to.value))
    |> set.union(current_nodes)

  let new_edges =
    split_edges
    |> set.from_list
    |> set.union(current_edges)

  #(new_nodes, new_edges)
}
