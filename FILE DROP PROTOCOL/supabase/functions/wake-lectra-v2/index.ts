import { corsHeaders, json } from "../_shared/cors.ts";
import { HttpError, requireAuthUser } from "../_shared/auth-user.ts";
import { admin, requireUuid } from "../_shared/device-auth.ts";
import {
  broadcastWakeHint,
  maybeSendLectraBackgroundPush,
  resolveMostRecentLectraDevice,
} from "../_shared/dropbridge-v2.ts";

type WakeLectraV2Payload = {
  syncedItemId?: string;
  reason?: string;
};

const DEFAULT_REASON = "synced_item_inserted";
const WAKE_EVENT = "document_refresh";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireAuthUser(request);
    const payload = (await request.json()) as WakeLectraV2Payload;
    const syncedItemId = String(payload.syncedItemId ?? "").trim();
    const reason = String(payload.reason ?? DEFAULT_REASON).trim() || DEFAULT_REASON;

    requireUuid(syncedItemId, "syncedItemId");

    const { data: item, error: itemError } = await admin
      .from("synced_items")
      .select("id, user_id, item_type")
      .eq("id", syncedItemId)
      .maybeSingle<{ id: string; user_id: string; item_type: string }>();

    if (itemError) {
      throw new Error(`Unable to load synced item: ${itemError.message}`);
    }

    if (!item) {
      return json({ error: "Synced item not found" }, 404);
    }

    if (item.user_id !== user.id) {
      return json({ error: "Synced item does not belong to this account" }, 403);
    }

    if (item.item_type !== "pdf_document") {
      return json({ error: "Only pdf_document rows can trigger Lectra wake hints" }, 409);
    }

    const device = await resolveMostRecentLectraDevice(user.id);
    if (!device) {
      return json({
        ok: true,
        deviceId: null,
        realtimeBroadcasted: false,
        apnsAttempted: false,
        apnsReason: "device_not_found",
      });
    }

    const realtimeBroadcasted = await broadcastWakeHint({
      userId: user.id,
      deviceId: device.id,
      event: WAKE_EVENT,
      payload: {
        syncedItemId,
        reason,
      },
    });

    const pushResult = await maybeSendLectraBackgroundPush({
      userId: user.id,
      deviceId: device.id,
      syncedItemId,
      reason,
    });

    return json({
      ok: true,
      deviceId: device.id,
      realtimeBroadcasted,
      apnsAttempted: pushResult.attempted,
      apnsReason: pushResult.reason,
    });
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }

    const message = error instanceof Error ? error.message : "Unknown error";
    const status = message.startsWith("Invalid") ? 400 : 500;
    return json({ error: message }, status);
  }
});
