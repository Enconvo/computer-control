import { sendHelperCommand } from "./_helper.js";

/** Read text parameters */
interface ReadParams {
    /** Element index from snapshot @eN reference. If omitted, reads from the frontmost window. */
    index?: number;
    /** Target application name */
    appName?: string;
    /** Maximum depth for nested content extraction @default 10 */
    maxDepth?: number;
}

/**
 * Extract text content from any app window or element subtree, with depth control for nested content. Recursively collects visible text from static text, text fields, headings, and links.
 * @param {Request} request - Request object, body is {@link ReadParams}
 * @returns Extracted text content and line count
 */
export default async function main(request: Request) {
    const params = (await request.json()) as ReadParams;
    return Response.json(await sendHelperCommand("read", params));
}
