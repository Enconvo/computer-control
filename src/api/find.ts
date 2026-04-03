import { findElements } from "./_helper.js";

/** Find elements parameters */
interface FindParams {
    /** Text query to search for (matches name, value, or description) */
    query?: string;
    /** Filter by AX role (e.g. "AXButton", "AXTextField"). Can omit "AX" prefix. */
    role?: string;
    /** Filter by name/title (case-insensitive partial match) */
    name?: string;
    /** Filter by value (case-insensitive partial match) */
    value?: string;
    /** Target application name */
    appName?: string;
    /** Maximum number of results @default 20 */
    maxResults?: number;
}

/**
 * Find elements in the AX tree by name, role, or value. Returns matching elements with position and metadata.
 * @param {Request} request - Request object, body is {@link FindParams}
 * @returns Array of matching elements
 */
export default async function main(request: Request) {
    const params = (await request.json()) as FindParams;
    const result = await findElements({
        name: params.query || params.name,
        role: params.role,
        value: params.value,
        appName: params.appName,
        maxResults: params.maxResults,
    });
    return Response.json(result);
}
