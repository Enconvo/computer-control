import { Commander } from "@enconvo/api";

/** Record audio parameters */
interface RecordAudioParams {
    /** Action to perform on the audio recording session @required */
    action: "start" | "pause" | "resume" | "stop" | "cancel" | "status";
    /** Output file path without extension. Only used by "start". Defaults to ~/Documents/.enconvo/MeetingRecordings/Recording-<timestamp> */
    outputPath?: string;
    /** Bundle IDs of apps to include in system audio capture. Empty array records all apps. Only used by "start". */
    includingApplications?: string[];
}

/** Response returned by the native audio recorder. Shape depends on action. */
interface RecordAudioResponse {
    data: {
        success?: boolean;
        error?: string;
        isRecording?: boolean;
        isPaused?: boolean;
        duration?: number;
        /** WAV file path. Populated on stop when recording succeeded. */
        path?: string;
    };
}

/**
 * Record system audio + microphone to a WAV file.
 *
 * Flow: call with `action: "start"` to begin, then optionally `pause` / `resume`,
 * and finally `stop` to receive the WAV file path. Use `cancel` to discard,
 * or `status` to query the current session.
 *
 * @param {Request} request - Request object, body is {@link RecordAudioParams}
 * @returns {@link RecordAudioResponse}
 */
export default async function main(request: Request) {
    const params = (await request.json()) as RecordAudioParams;
    console.log('record audio ', params.action)

    const payload: Record<string, any> = { action: params.action };
    if (params.outputPath !== undefined) payload.outputPath = params.outputPath;
    if (params.includingApplications !== undefined) {
        payload.includingApplications = params.includingApplications;
    }

    const result = (await Commander.send("recordAudio", payload)) as RecordAudioResponse;
    return Response.json(result.data ?? {});
}
