import { executeElementAction, pressKey } from "./_helper.js";

/** Fill/set value parameters */
interface FillParams {
    /** Element index from snapshot @eN reference @required */
    index: number;
    /** Value to set @required */
    value: string;
    /** Submit after filling (press Enter) @default false */
    submit?: boolean;
}

/**
 * Set the value of an input element directly (bypasses character-by-character typing). Use for text fields, text areas, and other editable elements.
 * @param {Request} request - Request object, body is {@link FillParams}
 * @returns Fill result with success status and the value that was set
 */
export default async function main(request: Request) {
    const params = (await request.json()) as FillParams;
    const { index, value, submit = false } = params;

    // Focus element first
    await executeElementAction(index, "setFocused");

    // Set value
    const result = await executeElementAction(index, "setValue", { value });

    if (submit && result.success) {
        await pressKey("return");
    }

    return Response.json(result);
}
