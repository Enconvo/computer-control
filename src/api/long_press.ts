import { sendHelperCommand } from "./_helper.js";

/** Long press parameters */
interface LongPressParams {
    /** Element index from snapshot @eN reference */
    index?: number;
    /** X coordinate for direct coordinate long press */
    x?: number;
    /** Y coordinate for direct coordinate long press */
    y?: number;
    /** Duration to hold in seconds @default 1.0 */
    duration?: number;
    /** Mouse button @default "left" */
    button?: "left" | "right";
}

/**
 * Press and hold at an element or coordinates for a duration. Useful for context menus, Force Touch previews, and drag initiation.
 * @param {Request} request - Request object, body is {@link LongPressParams}
 * @returns Long press result with coordinates and duration
 */
export default async function main(request: Request) {
    const params = (await request.json()) as LongPressParams;
    return Response.json(await sendHelperCommand("longPress", params));
}
