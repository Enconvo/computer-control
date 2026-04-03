import { sendHelperCommand } from "./_helper.js";

/** Inspect parameters */
interface InspectParams {
    /** Element index from snapshot @eN reference */
    index?: number;
    /** X coordinate to inspect element at point */
    x?: number;
    /** Y coordinate to inspect element at point */
    y?: number;
}

/**
 * Get complete metadata for one element: role, subrole, name, value, description, help text, position, size, actions, DOM id, identifier, editable state, and owning app. Accepts @eN index or x/y coordinates.
 * @param {Request} request - Request object, body is {@link InspectParams}
 * @returns Complete element metadata
 */
export default async function main(request: Request) {
    const params = (await request.json()) as InspectParams;
    return Response.json(await sendHelperCommand("inspect", params));
}
