import { executeElementAction } from "./_helper.js";

/** Get element info parameters */
interface GetElementInfoParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
}

/**
 * Get comprehensive information about an element: role, name, value, position, size, enabled, focused, child count, and available actions
 * @param {Request} request - Request object, body is {@link GetElementInfoParams}
 * @returns Detailed element info including role, subrole, name, title, value, description, enabled, focused, position, size, childCount, and actions
 */
export default async function main(request: Request) {
    const params = (await request.json()) as GetElementInfoParams;
    return Response.json(await executeElementAction(params.index, "getInfo"));
}
