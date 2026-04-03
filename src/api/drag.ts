import { sendHelperCommand } from "./_helper.js";

/** Drag parameters */
interface DragParams {
    /** Source element index @eN reference @required */
    fromIndex: number;
    /** Target element index @eN reference @required */
    toIndex: number;
    /** Duration of the drag in milliseconds @default 500 */
    duration?: number;
}

/**
 * Drag from one element to another using @eN snapshot references
 * @param {Request} request - Request object, body is {@link DragParams}
 * @returns Drag result with success status
 */
export default async function main(request: Request) {
    const params = (await request.json()) as DragParams;
    return Response.json(await sendHelperCommand("drag", params));
}
