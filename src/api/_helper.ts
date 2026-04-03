import { spawn, ChildProcess } from "child_process";
import { createInterface, Interface } from "readline";
import * as path from "path";
import * as fs from "fs";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ElementDescriptor {
    index: number;
    role: string;
    name: string;
    value: string | null;
    description: string;
    bounds: [number, number, number, number];
    enabled: boolean;
    subrole: string;
    pid: number;
}

export interface SnapshotResult {
    app: string;
    pid: number;
    tree: string;
    interactiveCount: number;
    windowTitle: string;
    windowBounds: [number, number, number, number] | null;
    elementMap: Record<string, ElementDescriptor>;
}

// ─── Swift Helper Process (persistent, like Chrome Extension for browser_control) ──

let _process: ChildProcess | null = null;
let _readline: Interface | null = null;
let _requestId = 0;
let _pendingRequests: Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }> = new Map();
let _ready = false;
let _helperPath: string | null = null;

function getHelperPath(): string {
    if (_helperPath) return _helperPath;

    const home = process.env.HOME || "/Users/" + process.env.USER;
    const candidates = [
        path.join(home, ".config/enconvo/extension/computer_control/assets/accessibility-helper"),
    ];

    for (const p of candidates) {
        if (fs.existsSync(p)) {
            _helperPath = p;
            return p;
        }
    }

    throw new Error(
        "Swift accessibility helper not found. Compile it with: cd swift-helper && swiftc -O -o ../assets/accessibility-helper AccessibilityHelper.swift -framework ApplicationServices -framework AppKit -framework CoreGraphics"
    );
}

function ensureHelper(): Promise<void> {
    if (_process && !_process.killed && _ready) {
        return Promise.resolve();
    }

    return new Promise((resolve, reject) => {
        try {
            const helperPath = getHelperPath();
            _process = spawn(helperPath, [], {
                stdio: ["pipe", "pipe", "pipe"],
            });

            _readline = createInterface({ input: _process.stdout! });

            _readline.on("line", (line: string) => {
                try {
                    const data = JSON.parse(line);

                    // Handle ready signal
                    if (data.ready) {
                        _ready = true;
                        resolve();
                        return;
                    }

                    // Handle response
                    const id = data.id;
                    const pending = _pendingRequests.get(id);
                    if (pending) {
                        _pendingRequests.delete(id);
                        delete data.id;
                        pending.resolve(data);
                    }
                } catch {
                    // ignore parse errors
                }
            });

            _process.stderr?.on("data", (data: Buffer) => {
                const msg = data.toString().trim();
                if (msg) console.error("[accessibility-helper]", msg);
            });

            _process.on("exit", (code) => {
                _ready = false;
                _process = null;
                _readline = null;
                // Reject all pending requests
                for (const [, pending] of _pendingRequests) {
                    pending.reject(new Error(`Helper process exited with code ${code}`));
                }
                _pendingRequests.clear();
            });

            _process.on("error", (err) => {
                _ready = false;
                reject(err);
            });

            // Timeout for startup
            setTimeout(() => {
                if (!_ready) reject(new Error("Helper process did not start within 5s"));
            }, 5000);
        } catch (e) {
            reject(e);
        }
    });
}

/**
 * Send a command to the Swift accessibility helper and return the result.
 * This is the core communication function — equivalent to browser_control's sendBrowserAction().
 */
export async function sendHelperCommand(method: string, params: Record<string, any> = {}): Promise<any> {
    await ensureHelper();

    const id = ++_requestId;

    return new Promise((resolve, reject) => {
        _pendingRequests.set(id, { resolve, reject });

        const request = JSON.stringify({ id, method, params }) + "\n";
        _process!.stdin!.write(request, (err) => {
            if (err) {
                _pendingRequests.delete(id);
                reject(err);
            }
        });

        // Timeout per request
        setTimeout(() => {
            if (_pendingRequests.has(id)) {
                _pendingRequests.delete(id);
                reject(new Error(`Request ${method} timed out after 30s`));
            }
        }, 30000);
    });
}

// ─── Public API (matches existing endpoint signatures) ───────────────────────

export async function buildSnapshot(options: {
    appName?: string;
    pid?: number;
    interactiveOnly?: boolean;
    maxDepth?: number;
} = {}): Promise<SnapshotResult> {
    const result = await sendHelperCommand("snapshot", options);
    if (!result.success && result.error) {
        throw new Error(result.error);
    }
    return result;
}

export async function executeElementAction(
    index: number,
    action: string,
    actionParams: Record<string, any> = {}
): Promise<any> {
    // Map action names to helper methods
    const methodMap: Record<string, string> = {
        click: "click",
        setValue: "setValue",
        setFocused: "focus",
        confirm: "performAction",
        cancel: "performAction",
        showMenu: "performAction",
        increment: "performAction",
        decrement: "performAction",
        pick: "performAction",
        getInfo: "getInfo",
        getText: "getText",
        getAttribute: "getInfo", // getInfo returns all attributes
        performAction: "performAction",
    };

    const method = methodMap[action] || action;
    const params: Record<string, any> = { index, ...actionParams };

    // For performAction, pass the action name
    if (["confirm", "cancel", "showMenu", "increment", "decrement", "pick"].includes(action)) {
        const axActionMap: Record<string, string> = {
            confirm: "AXConfirm", cancel: "AXCancel", showMenu: "AXShowMenu",
            increment: "AXIncrement", decrement: "AXDecrement", pick: "AXPick",
        };
        params.actionName = axActionMap[action];
    }

    return sendHelperCommand(method, params);
}

export async function pressKey(key: string, modifiers: string[] = []): Promise<any> {
    return sendHelperCommand("press", { key, modifiers });
}

export async function typeText(text: string, delayMs = 0): Promise<any> {
    return sendHelperCommand("type", { text, delay: delayMs });
}

export async function mouseAction(
    action: "move" | "click" | "doubleClick" | "rightClick" | "mouseDown" | "mouseUp",
    x: number,
    y: number
): Promise<any> {
    return sendHelperCommand("mouse", { action, x, y });
}

export async function scrollAction(
    direction: "up" | "down" | "left" | "right",
    amount = 3
): Promise<any> {
    return sendHelperCommand("scroll", { direction, amount });
}

export async function captureScreenshot(options: {
    filePath: string;
    format?: "png" | "jpg";
}): Promise<string> {
    const result = await sendHelperCommand("screenshot", { filePath: options.filePath });
    if (!result.success) throw new Error(result.error);
    return result.filePath;
}

export async function listRunningApps(): Promise<any> {
    const result = await sendHelperCommand("apps", {});
    return result.apps || [];
}

export async function listWindows(appName?: string): Promise<any> {
    const result = await sendHelperCommand("windows", { appName });
    return result.windows || [];
}

export async function openApp(appName: string): Promise<any> {
    return sendHelperCommand("openApp", { appName });
}

export async function findElements(options: {
    appName?: string;
    role?: string;
    name?: string;
    value?: string;
    maxResults?: number;
}): Promise<any> {
    return sendHelperCommand("find", options);
}

export function getCachedElement(index: number): ElementDescriptor | undefined {
    // In the Swift helper architecture, elements are cached in the Swift process.
    // We keep a local mirror for bounds/metadata checks in endpoints like is_visible.
    return _localElementCache.get(index);
}

export function getCacheInfo(): { app: string; pid: number; count: number } {
    return { app: _localCacheApp, pid: _localCachePid, count: _localElementCache.size };
}

// Local mirror of element metadata (updated after each snapshot)
let _localElementCache: Map<number, ElementDescriptor> = new Map();
let _localCacheApp = "";
let _localCachePid = 0;

// Override buildSnapshot to also update local cache
const _originalBuildSnapshot = buildSnapshot;
export { _originalBuildSnapshot };

// Patch: after snapshot, update local cache
const origBuildSnapshotFn = buildSnapshot;
export async function buildSnapshotAndCache(options: {
    appName?: string;
    pid?: number;
    interactiveOnly?: boolean;
    maxDepth?: number;
} = {}): Promise<SnapshotResult> {
    const result = await origBuildSnapshotFn(options);
    _localElementCache.clear();
    _localCacheApp = result.app || "";
    _localCachePid = result.pid || 0;
    if (result.elementMap) {
        for (const [k, v] of Object.entries(result.elementMap)) {
            _localElementCache.set(Number(k), v as ElementDescriptor);
        }
    }
    return result;
}
