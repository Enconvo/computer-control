import { getCachedElement } from "./_helper.js";

/** Visibility check parameters */
interface IsVisibleParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
}

/**
 * Check if an element is visible (has non-zero bounds and is within the screen area)
 * @param {Request} request - Request object, body is {@link IsVisibleParams}
 * @returns Visibility status of the element
 */
export default async function main(request: Request) {
    const params = (await request.json()) as IsVisibleParams;
    const element = getCachedElement(params.index);

    if (!element) {
        return Response.json({
            success: false,
            error: `Element @e${params.index} not found. Run snapshot first.`,
        });
    }

    const [x, y, w, h] = element.bounds;
    const isVisible = w > 0 && h > 0 && x >= 0 && y >= 0;

    return Response.json({
        success: true,
        visible: isVisible,
        bounds: { x, y, width: w, height: h },
    });
}
