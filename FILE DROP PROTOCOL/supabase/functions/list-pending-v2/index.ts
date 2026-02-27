import { corsHeaders, json } from "../_shared/cors.ts";
import { admin, requireUuid } from "../_shared/device-auth.ts";
import { HttpError, requireAuthUser } from "../_shared/auth-user.ts";

type PendingV2Payload = {
  deviceId?: string;
  limit?: number;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireAuthUser(request);
    const payload = (await request.json()) as PendingV2Payload;
    const deviceId = String(payload.deviceId ?? "").trim();
    const limit = Math.max(1, Math.min(Number(payload.limit ?? 5), 10));

    requireUuid(deviceId, "deviceId");

    const { data: device, error: deviceError } = await admin
      .from("devices")
      .select("id, user_id, revoked_at, client_kind")
      .eq("id", deviceId)
      .maybeSingle();

    if (deviceError) {
      throw new Error(`Unable to look up device: ${deviceError.message}`);
    }

    if (!device) {
      return json({ error: "Device not found" }, 404);
    }

    if (device.user_id !== user.id || device.client_kind !== "canvascope_extension" || device.revoked_at) {
      return json({ error: "Device does not belong to this account" }, 403);
    }

    await admin
      .from("devices")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("id", deviceId);

    const nowIso = new Date().toISOString();
    const staleClaimCutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString();

    await admin
      .from("uploads")
      .update({ status: "queued", claimed_at: null })
      .eq("user_id", user.id)
      .eq("device_id", deviceId)
      .eq("status", "downloading")
      .gt("expires_at", nowIso)
      .lt("claimed_at", staleClaimCutoff);

    await admin
      .from("uploads")
      .update({ status: "canceled", claimed_at: null })
      .eq("user_id", user.id)
      .eq("device_id", deviceId)
      .in("status", ["queued", "downloading"])
      .lte("expires_at", nowIso);

    const { data: queuedRows, error: queueError } = await admin
      .from("uploads")
      .select("id")
      .eq("user_id", user.id)
      .eq("device_id", deviceId)
      .eq("status", "queued")
      .gt("expires_at", nowIso)
      .order("created_at", { ascending: true })
      .limit(limit);

    if (queueError) {
      throw new Error(`Unable to list pending uploads: ${queueError.message}`);
    }

    if (!queuedRows || queuedRows.length === 0) {
      return json({ ok: true, uploads: [] });
    }

    const ids = queuedRows.map((row) => row.id);

    const { data: claimedRows, error: claimError } = await admin
      .from("uploads")
      .update({
        status: "downloading",
        claimed_at: new Date().toISOString(),
      })
      .in("id", ids)
      .eq("user_id", user.id)
      .eq("device_id", deviceId)
      .eq("status", "queued")
      .select("id, file_name, object_path, mime_type, size_bytes, created_at, expires_at");

    if (claimError) {
      throw new Error(`Unable to claim uploads: ${claimError.message}`);
    }

    if (!claimedRows || claimedRows.length === 0) {
      return json({ ok: true, uploads: [] });
    }

    const uploads = [];

    for (const row of claimedRows) {
      const { data: signedData, error: signedError } = await admin.storage
        .from("drops")
        .createSignedUrl(row.object_path, 60 * 5);

      if (signedError || !signedData?.signedUrl) {
        await admin
          .from("uploads")
          .update({ status: "queued", claimed_at: null })
          .eq("id", row.id)
          .eq("user_id", user.id)
          .eq("device_id", deviceId);
        continue;
      }

      uploads.push({
        id: row.id,
        uploadId: row.id,
        fileName: row.file_name,
        mimeType: row.mime_type,
        sizeBytes: row.size_bytes,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
        downloadUrl: signedData.signedUrl,
      });
    }

    return json({ ok: true, uploads });
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }

    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message.startsWith("Invalid") ? 400 : 500;
    return json({ error: message }, status);
  }
});
