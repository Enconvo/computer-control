import { executeElementAction } from "./_helper.js";

/** Focus parameters */
interface FocusParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
}

/**
 * Set keyboard focus to an element identified by @eN index
 * @param {Request} request - Request object, body is {@link FocusParams}
 * @returns Focus result with success status
 */
export default async function main(request: Request) {
    const params = (await request.json()) as FocusParams;
    const result = await executeElementAction(params.index, "setFocused");
    if (!result.success) {
        // Fallback: try clicking to focus
        return Response.json(await executeElementAction(params.index, "click"));
    }
    return Response.json(result);
}
