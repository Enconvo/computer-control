import { getCachedElement, mouseAction } from "./_helper.js";

/** Hover parameters */
interface HoverParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
}

/**
 * Move the mouse cursor to hover over an element identified by @eN index
 * @param {Request} request - Request object, body is {@link HoverParams}
 * @returns Hover result with success status and coordinates
 */
export default async function main(request: Request) {
    const params = (await request.json()) as HoverParams;
    const element = getCachedElement(params.index);
    if (!element) {
        return Response.json({
            success: false,
            error: `Element @e${params.index} not found. Run snapshot first.`,
        });
    }
    const x = element.bounds[0] + element.bounds[2] / 2;
    const y = element.bounds[1] + element.bounds[3] / 2;
    return Response.json(await mouseAction("move", x, y));
}
