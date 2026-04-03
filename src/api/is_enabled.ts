import { getCachedElement } from "./_helper.js";

/** Enabled check parameters */
interface IsEnabledParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
}

/**
 * Check if an element is enabled (not disabled/grayed out)
 * @param {Request} request - Request object, body is {@link IsEnabledParams}
 * @returns Enabled status of the element
 */
export default async function main(request: Request) {
    const params = (await request.json()) as IsEnabledParams;
    const element = getCachedElement(params.index);

    if (!element) {
        return Response.json({
            success: false,
            error: `Element @e${params.index} not found. Run snapshot first.`,
        });
    }

    return Response.json({
        success: true,
        enabled: element.enabled,
        role: element.role,
        name: element.name,
    });
}
