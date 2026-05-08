---
name: computer-use
description: >
  Control any macOS application using the Accessibility API. Navigate UI trees, click elements, type text, take screenshots, read content, scroll, and more. Works with any app that supports macOS accessibility — Finder, System Settings, Notes, Xcode, and beyond.
metadata:
  author: EnconvoAI
  version: "0.0.48"
---

## API Reference

Just use the `local_api` tool to request these APIs.

| Endpoint | Description |
|----------|-------------|
| `computer-use/annotated_screenshot` | Capture a screenshot with numbered Set-of-Marks labels drawn on interactive elements (zero ML, instant). Returns the annotated image and a text index with click coordinates.. Params: `appName` (string), `maxLabels` (number, default: 50) |
| `computer-use/apps` | List all running foreground applications with their name, PID, frontmost status, and visibility. _No params_ |
| `computer-use/batch` | Execute multiple computer control actions in sequence within a single request. Reduces round-trip latency for multi-step workflows.. Params: `actions` (array, required), `stopOnError` (boolean, default: false) |
| `computer-use/click` | Click an element by @eN index (AX API), text query (AX find + coordinate click), or x/y coordinates (CGEvent fallback). _6 params — use `check_local_api_schemas` tool_ |
| `computer-use/context` | Get orientation context: frontmost app, window title, focused element. Helps agents understand the current state before acting.. _No params_ |
| `computer-use/drag` | Drag from one element to another using @eN snapshot references. Params: `fromIndex` (number, required), `toIndex` (number, required), `duration` (number, default: 500) |
| `computer-use/element_at` | Identify what element is at a specific screen coordinate. Returns full metadata: role, name, value, position, size, actions, and owning app.. Params: `x` (number, required), `y` (number, required) |
| `computer-use/fill` | Set the value of an input element directly (bypasses character-by-character typing). Use for text fields, text areas, and other editable elements.. Params: `index` (number, required), `value` (string, required), `submit` (boolean, default: false) |
| `computer-use/find` | Find elements in the AX tree by name, role, or value. Returns matching elements with position and metadata.. _6 params — use `check_local_api_schemas` tool_ |
| `computer-use/focus` | Set keyboard focus to an element identified by @eN index. Params: `index` (number, required) |
| `computer-use/get_attribute` | Get a specific accessibility attribute from an element by @eN index. Params: `index` (number, required), `attribute` (string, default: "AXValue") |
| `computer-use/get_content` | Get the text content of the current window from the frontmost (or specified) application. Returns app name, window title, and all visible text.. Params: `appName` (string), `includeTree` (boolean, default: true) |
| `computer-use/get_element_info` | Get comprehensive information about an element: role, name, value, position, size, enabled, focused, child count, and available actions. Params: `index` (number, required) |
| `computer-use/get_text` | Get the text content of an element by @eN index. Returns the element's value, name, title, or description — whichever is available.. Params: `index` (number, required) |
| `computer-use/hotkey` | Press a key combination like Cmd+L, Cmd+Return, Cmd+Shift+P. Modifiers are held while the final key is pressed.. Params: `keys` (array, required) |
| `computer-use/hover` | Move the mouse cursor to hover over an element identified by @eN index. Params: `index` (number, required) |
| `computer-use/inspect` | Get complete metadata for one element: role, subrole, name, value, description, help text, position, size, actions, DOM id, identifier, editable state, and owning app. Accepts @eN index or x/y coordinates.. Params: `index` (number), `x` (number), `y` (number) |
| `computer-use/is_enabled` | Check if an element is enabled (not disabled/grayed out). Params: `index` (number, required) |
| `computer-use/is_visible` | Check if an element is visible (has non-zero bounds and is within the screen area). Params: `index` (number, required) |
| `computer-use/long_press` | Press and hold at an element or coordinates for a duration. Useful for context menus, Force Touch previews, and drag initiation.. _5 params — use `check_local_api_schemas` tool_ |
| `computer-use/mouse` | Low-level mouse control: move, click, double-click, right-click, mouse down/up at specific screen coordinates. Params: `action` (string, required), `x` (number, required), `y` (number, required) |
| `computer-use/open_app` | Open (activate) a macOS application by name. If already running, brings it to the foreground.. Params: `appName` (string, required) |
| `computer-use/press` | Press a keyboard key or shortcut (e.g. Cmd+C, Enter, Escape). Works globally — sends to the frontmost application.. Params: `key` (string, required), `modifiers` (array) |
| `computer-use/read` | Extract text content from any app window or element subtree, with depth control for nested content. Recursively collects visible text from static text, text fields, headings, and links.. Params: `index` (number), `appName` (string), `maxDepth` (number, default: 10) |
| `computer-use/record_audio` | Record system audio + microphone to a WAV file. Flow: call with `action: "start"` to begin, then optionally `pause` / `resume`, and finally `stop` to receive the WAV file path. Use `cancel` to discard, or `status` to query the current session.. _6 params — use `check_local_api_schemas` tool_ |
| `computer-use/run_applescript` | Execute an AppleScript or JXA (JavaScript for Automation) script and return the result. Params: `script` (string, required), `language` (string, default: "applescript"), `timeout` (number, default: 30000) |
| `computer-use/screenshot` | Capture a screenshot of the entire screen and return as a displayable image. Params: `format` (string, default: "png") |
| `computer-use/scroll` | Scroll the page in a direction or scroll a specific element into view. Params: `direction` (string, default: "down"), `amount` (number, default: 3), `index` (number) |
| `computer-use/snapshot` | Generate an accessibility tree snapshot with @eN references using the AX API with semantic depth tunneling.. _4 params — use `check_local_api_schemas` tool_ |
| `computer-use/state` | List every running app with its windows, positions, and sizes. Provides a unified view of the entire desktop state.. _No params_ |
| `computer-use/status` | Get the current status of the computer control module: cached element count, target app, and running apps summary. _No params_ |
| `computer-use/type` | Type text character by character using keyboard events. Optionally focus an element first by @eN index.. Params: `text` (string, required), `index` (number), `delay` (number, default: 0) |
| `computer-use/wait` | Wait for a condition to be met (element appears/disappears, title changes, or fixed delay). Polls at the specified interval until timeout.. _5 params — use `check_local_api_schemas` tool_ |
| `computer-use/window` | Manage application windows: list, minimize, maximize, restore, close, move, or resize any window.. _7 params — use `check_local_api_schemas` tool_ |
| `computer-use/windows` | List all windows of an application with their index, title, position, size, and minimized status. Params: `appName` (string) |

