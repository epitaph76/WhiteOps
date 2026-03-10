# WhiteOps Orchestrator Desktop

Desktop Flutter frontend for visual orchestration graph editing and execution.

## Features

- Visual graph editor screen (canvas + right palette).
- Drag-and-drop nodes from palette onto canvas.
- Move nodes, create directed edges by dragging from output port.
- Edit edge relation types (`manager_to_worker`, `dependency`, `peer`, `feedback`).
- Node inspector for label/type/agent/role/timeout/cwd/retry settings.
- Node dialog modals:
  - manager view: chat + manager decisions + worker progress;
  - worker view: chat + task + logs + final result/artifacts.
- Realtime graph-run updates via SSE (`GET /graph-runs/:runId/events`).
- Save/load graph in backend (`/graphs`) and local draft JSON file.
- Zoom/pan, snap-to-grid, minimap, multi-select and hotkeys.

## Run

1. Start backend services (`cli-bridge` and `orchestrator`).
2. Open this folder:
   - `cd apps/orchestrator_desktop`
3. Install dependencies:
   - `flutter pub get`
4. Run desktop app:
   - `flutter run -d windows`

The default orchestrator URL is `http://127.0.0.1:7081`. You can change it in the UI header.

## Notes

- This app is desktop-first (wide split layout), but still adapts to narrow windows.
- Hotkeys: `Delete`, `Esc`, `Ctrl/Cmd+A`, `Ctrl/Cmd+S`, `Ctrl/Cmd+Shift+S`, `Ctrl/Cmd+L`.
- Local draft file path: `apps/orchestrator_desktop/orchestration_graph_local.json` (relative to current working directory).
