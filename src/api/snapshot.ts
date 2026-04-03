import { buildSnapshotAndCache } from "./_helper.js";

/** Accessibility tree snapshot parameters */
interface SnapshotParams {
    /** Only include interactive elements (buttons, inputs, etc.) in the tree @default false */
    interactiveOnly?: boolean;
    /** Maximum UI tree traversal depth (uses semantic depth tunneling — empty layout containers cost 0) @default 25 */
    maxDepth?: number;
    /** Target application name. If omitted, uses the frontmost application */
    appName?: string;
    /** Target process ID. Overrides appName if specified */
    pid?: number;
}

/**
 * Generate an accessibility tree snapshot with @eN references using the AX API with semantic depth tunneling.
 * @param {Request} request - Request object, body is {@link SnapshotParams}
 * @returns Snapshot result with tree text, reference count, app name, PID, and window metadata
 */
export default async function main(request: Request) {
    const params = (await request.json()) as SnapshotParams;

    try {
        const result = await buildSnapshotAndCache(params);
        return Response.json({
            success: true,
            app: result.app,
            pid: result.pid,
            tree: result.tree,
            interactiveCount: result.interactiveCount,
            windowTitle: result.windowTitle,
            windowBounds: result.windowBounds,
        });
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
