import { GraphEdge, GraphNode, GraphValidationResult } from "./graph-types";

function isExecutionEdge(edge: GraphEdge): boolean {
  // Feedback edges are informational and must not participate in execution DAG validation.
  return edge.relationType !== "feedback";
}

export function validateGraph(nodes: GraphNode[], edges: GraphEdge[]): GraphValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  if (nodes.length === 0) {
    warnings.push("Graph has no nodes");
  }

  const nodeIds = new Set<string>();
  for (const node of nodes) {
    if (nodeIds.has(node.id)) {
      errors.push(`Duplicate node id: ${node.id}`);
      continue;
    }
    nodeIds.add(node.id);
  }

  const edgeIds = new Set<string>();
  const validEdges: GraphEdge[] = [];
  for (const edge of edges) {
    if (edgeIds.has(edge.id)) {
      errors.push(`Duplicate edge id: ${edge.id}`);
      continue;
    }
    edgeIds.add(edge.id);

    if (!nodeIds.has(edge.fromNodeId)) {
      errors.push(`Edge ${edge.id} references missing fromNodeId: ${edge.fromNodeId}`);
      continue;
    }

    if (!nodeIds.has(edge.toNodeId)) {
      errors.push(`Edge ${edge.id} references missing toNodeId: ${edge.toNodeId}`);
      continue;
    }

    if (edge.fromNodeId === edge.toNodeId) {
      errors.push(`Edge ${edge.id} cannot reference the same node on both sides`);
      continue;
    }

    validEdges.push(edge);
  }

  const outgoing = new Map<string, string[]>();
  const indegree = new Map<string, number>();

  for (const node of nodes) {
    outgoing.set(node.id, []);
    indegree.set(node.id, 0);
  }

  for (const edge of validEdges.filter(isExecutionEdge)) {
    outgoing.get(edge.fromNodeId)?.push(edge.toNodeId);
    indegree.set(edge.toNodeId, (indegree.get(edge.toNodeId) ?? 0) + 1);
  }

  const queue: string[] = [...nodes]
    .map((node) => node.id)
    .filter((nodeId) => (indegree.get(nodeId) ?? 0) === 0);
  const topologicalOrder: string[] = [];

  while (queue.length > 0) {
    const nodeId = queue.shift();
    if (!nodeId) {
      break;
    }

    topologicalOrder.push(nodeId);
    for (const child of outgoing.get(nodeId) ?? []) {
      const next = (indegree.get(child) ?? 0) - 1;
      indegree.set(child, next);
      if (next === 0) {
        queue.push(child);
      }
    }
  }

  if (topologicalOrder.length !== nodes.length) {
    const cycleNodes = nodes
      .map((node) => node.id)
      .filter((nodeId) => (indegree.get(nodeId) ?? 0) > 0);
    errors.push(`Graph contains a cycle. Problematic nodes: ${cycleNodes.join(", ")}`);
  }

  const managerCount = nodes.filter(
    (node) => node.type === "manager" || node.config.role === "manager",
  ).length;
  if (managerCount === 0 && nodes.length > 0) {
    warnings.push("Graph has no manager node");
  }

  const workerCount = nodes.filter(
    (node) => node.type === "worker" || node.config.role === "worker",
  ).length;
  if (workerCount === 0 && nodes.length > 0) {
    warnings.push("Graph has no worker nodes");
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
    topologicalOrder,
  };
}
