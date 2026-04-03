import { sendHelperCommand, executeElementAction, mouseAction } from "./_helper.js";

/** Element click parameters */
interface ClickParams {
    /** Element index from snapshot @eN reference (e.g. 0 for @e0). Uses AX API. */
    index?: number;
    /** Text query to find and click element (AX find then click at center coordinates) */
    query?: string;
    /** X coordinate for direct coordinate click (CGEvent fallback) */
    x?: number;
    /** Y coordinate for direct coordinate click (CGEvent fallback) */
    y?: number;
    /** Mouse button @default "left" */
    button?: "left" | "right";
    /** Number of clicks (2 for double-click) @default 1 */
    clickCount?: number;
}

/**
 * Click an element by @eN index (AX API), text query (AX find + coordinate click), or x/y coordinates (CGEvent fallback)
 * @param {Request} request - Request object, body is {@link ClickParams}
 * @returns Click result with success status
 */
export default async function main(request: Request) {
    const params = (await request.json()) as ClickParams;

    // AX index click
    if (params.index !== undefined) {
        const result = await executeElementAction(params.index, "click", { button: params.button });
        return Response.json(result);
    }

    // Coordinate click (CGEvent fallback)
    if (params.x !== undefined && params.y !== undefined) {
        const action = params.clickCount === 2 ? "doubleClick"
            : params.button === "right" ? "rightClick"
            : "click";
        const result = await mouseAction(action, params.x, params.y);
        return Response.json(result);
    }

    // Query: AX find then click at center coordinates
    if (params.query) {
        const found = await sendHelperCommand("find", { name: params.query, maxResults: 1 });
        if (found.results?.length > 0) {
            const el = found.results[0];
            const cx = (el.position?.[0] || 0) + ((el.size?.[0] || 0) / 2);
            const cy = (el.position?.[1] || 0) + ((el.size?.[1] || 0) / 2);
            const action = params.clickCount === 2 ? "doubleClick"
                : params.button === "right" ? "rightClick"
                : "click";
            const result = await mouseAction(action, cx, cy);
            return Response.json({ ...result, element: el });
        }
        return Response.json({
            success: false,
            error: `Could not find element matching "${params.query}"`,
            suggestion: "Try snapshot to see available elements, or provide x/y coordinates.",
        });
    }

    return Response.json({
        success: false,
        error: "No index, query, or coordinates provided",
    });
}
