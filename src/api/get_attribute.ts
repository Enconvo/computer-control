import { executeElementAction } from "./_helper.js";

/** Get attribute parameters */
interface GetAttributeParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
    /** Accessibility attribute name (e.g. "AXValue", "AXTitle", "AXRole", "AXDescription", "AXHelp") @default "AXValue" */
    attribute?: string;
}

/**
 * Get a specific accessibility attribute from an element by @eN index
 * @param {Request} request - Request object, body is {@link GetAttributeParams}
 * @returns Attribute name and its value
 */
export default async function main(request: Request) {
    const params = (await request.json()) as GetAttributeParams;
    return Response.json(
        await executeElementAction(params.index, "getAttribute", {
            attribute: params.attribute || "AXValue",
        })
    );
}
