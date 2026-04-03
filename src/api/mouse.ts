import { mouseAction } from "./_helper.js";

/** Mouse control parameters */
interface MouseParams {
    /** Mouse action to perform @required */
    action: "move" | "click" | "doubleClick" | "rightClick" | "mouseDown" | "mouseUp";
    /** X coordinate (screen pixels from left) @required */
    x: number;
    /** Y coordinate (screen pixels from top) @required */
    y: number;
}

/**
 * Low-level mouse control: move, click, double-click, right-click, mouse down/up at specific screen coordinates
 * @param {Request} request - Request object, body is {@link MouseParams}
 * @returns Mouse action result with coordinates
 */
export default async function main(request: Request) {
    const params = (await request.json()) as MouseParams;
    const { action, x, y } = params;

    try {
        return Response.json(await mouseAction(action, x, y));
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
