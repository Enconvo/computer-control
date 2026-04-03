import { scrollAction, getCachedElement, mouseAction } from "./_helper.js";

/** Scroll parameters */
interface ScrollParams {
    /** Scroll direction @default "down" */
    direction?: "up" | "down" | "left" | "right";
    /** Scroll amount (number of scroll units, each ~3 lines) @default 3 */
    amount?: number;
    /** Element index to scroll into view (overrides direction/amount). Uses @eN ref from snapshot. */
    index?: number;
}

/**
 * Scroll the page in a direction or scroll a specific element into view
 * @param {Request} request - Request object, body is {@link ScrollParams}
 * @returns Scroll result with success status
 */
export default async function main(request: Request) {
    const params = (await request.json()) as ScrollParams;
    const { direction = "down", amount = 3, index } = params;

    if (index !== undefined) {
        // Scroll element into view by clicking it (which triggers scroll-to-visible)
        const element = getCachedElement(index);
        if (!element) {
            return Response.json({
                success: false,
                error: `Element @e${index} not found. Run snapshot first.`,
            });
        }
        // Move mouse to element center to ensure it's the scroll target
        const x = element.bounds[0] + element.bounds[2] / 2;
        const y = element.bounds[1] + element.bounds[3] / 2;
        await mouseAction("move", x, y);
        return Response.json({ success: true, action: "scrollToElement", index });
    }

    return Response.json(await scrollAction(direction, amount));
}
