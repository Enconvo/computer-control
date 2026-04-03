import { executeElementAction } from "./_helper.js";

/** Get text parameters */
interface GetTextParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
}

/**
 * Get the text content of an element by @eN index. Returns the element's value, name, title, or description — whichever is available.
 * @param {Request} request - Request object, body is {@link GetTextParams}
 * @returns Text content of the element
 */
export default async function main(request: Request) {
    const params = (await request.json()) as GetTextParams;
    return Response.json(await executeElementAction(params.index, "getText"));
}
