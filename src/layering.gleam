import aonyx/graph

// We add an Int to the key of the nodes
// this Int is the index of the layer. 0 is bottom.
pub fn minimize_number_of_layers(
  graph: graph.Graph(key, value, label),
) -> graph.Graph(#(key, Int), value, label) {
    // extract all sources (all nodes with only outgoing edges)
    // for each source q, set its layer to 0
    
  todo
}
