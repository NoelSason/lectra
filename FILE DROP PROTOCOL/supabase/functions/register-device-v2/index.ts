import { corsHeaders, json } from "../_shared/cors.ts";
import { admin, requireUuid } from "../_shared/device-auth.ts";
import { HttpError, requireAuthUser } from "../_shared/auth-user.ts";
import { normalizeClientKind } from "../_shared/dropbridge-v2.ts";

type RegisterDeviceV2Payload = {
  deviceId?: string;
  deviceName?: string;
  clientKind?: "canvascope_extension" | "lectra_ipad";
  pushToken?: string | null;
  pushEnvironment?: "sandbox" | "production" | null;
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
    const payload = (await request.json()) as RegisterDeviceV2Payload;
    const deviceId = String(payload.deviceId ?? "").trim();
    const rawClientKind = String(payload.clientKind ?? "").trim();
    if (rawClientKind && rawClientKind !== "canvascope_extension" && rawClientKind !== "lectra_ipad") {
      return json({ error: "clientKind must be canvascope_extension or lectra_ipad" }, 400);
    }

    const clientKind = normalizeClientKind(payload.clientKind, "canvascope_extension");
    const defaultName = clientKind === "lectra_ipad" ? "Lectra iPad" : "Canvascope Receiver";
    const deviceName = String(payload.deviceName ?? defaultName)
      .trim()
      .slice(0, 64) || defaultName;
    const pushTokenProvided = Object.prototype.hasOwnProperty.call(payload, "pushToken");
    const pushEnvironmentProvided = Object.prototype.hasOwnProperty.call(payload, "pushEnvironment");
    const normalizedPushToken = pushTokenProvided
      ? (String(payload.pushToken ?? "").trim() || null)
      : undefined;
    const rawPushEnvironment = pushEnvironmentProvided
      ? String(payload.pushEnvironment ?? "").trim()
      : undefined;

    if (
      rawPushEnvironment !== undefined &&
      rawPushEnvironment !== "" &&
      rawPushEnvironment !== "sandbox" &&
      rawPushEnvironment !== "production"
    ) {
      return json({ error: "pushEnvironment must be sandbox or production" }, 400);
    }

    requireUuid(deviceId, "deviceId");

    const { data: existing, error: existingError } = await admin
      .from("devices")
      .select("id, user_id")
      .eq("id", deviceId)
      .maybeSingle();

    if (existingError) {
      throw new Error(`Failed to check existing device: ${existingError.message}`);
    }

    if (existing?.user_id && existing.user_id !== user.id) {
      return json({ error: "Device belongs to another account" }, 409);
    }

    const now = new Date().toISOString();
    const deviceUpsert: Record<string, string | null> = {
      id: deviceId,
      user_id: user.id,
      name: deviceName,
      client_kind: clientKind,
      revoked_at: null,
      last_seen_at: now,
    };

    if (pushTokenProvided) {
      deviceUpsert.push_token = normalizedPushToken ?? null;
    }

    if (pushEnvironmentProvided) {
      deviceUpsert.push_environment = rawPushEnvironment ? rawPushEnvironment : null;
    } else if (pushTokenProvided && normalizedPushToken === null) {
      deviceUpsert.push_environment = null;
    }

    if (pushTokenProvided || pushEnvironmentProvided) {
      deviceUpsert.push_token_updated_at = now;
    }

    const { error: upsertError } = await admin.from("devices").upsert(deviceUpsert, {
      onConflict: "id",
    });

    if (upsertError) {
      throw new Error(`Failed to register device: ${upsertError.message}`);
    }

    return json({
      ok: true,
      deviceId,
      deviceName,
      userId: user.id,
      lastSeenAt: now,
      pushTokenUpdatedAt: pushTokenProvided || pushEnvironmentProvided ? now : null,
      pushEnvironment: pushEnvironmentProvided
        ? (rawPushEnvironment ? rawPushEnvironment : null)
        : null,
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
