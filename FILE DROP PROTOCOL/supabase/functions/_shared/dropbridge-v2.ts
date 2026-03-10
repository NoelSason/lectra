import { importPKCS8, SignJWT, type KeyLike } from "npm:jose@5.9.6";

import { admin } from "./device-auth.ts";

export type DropBridgeClientKind = "canvascope_extension" | "lectra_ipad";

type PushEnvironment = "sandbox" | "production";

type PushTarget = {
  id: string;
  user_id: string;
  client_kind: string;
  push_token: string | null;
  push_environment: PushEnvironment | null;
  last_seen_at?: string | null;
};

export type MaybePushResult =
  | { attempted: false; reason: string }
  | { attempted: true; reason: "sent" };

const ACTIVE_RECEIVER_WINDOW_MS = 12 * 60 * 1000;
const APNS_MIN_PUSH_INTERVAL_SECONDS = 30;
const APNS_JWT_TTL_MS = 50 * 60 * 1000;
const APNS_ENDPOINTS: Record<PushEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

type ApnsConfig = {
  keyId: string;
  teamId: string;
  topic: string;
  privateKeyPem: string;
};

let apnsSigningKeyCache: { pem: string; key: KeyLike } | null = null;
let apnsJwtCache: { token: string; expiresAtMs: number; cacheKey: string } | null = null;

export function normalizeClientKind(
  value: unknown,
  fallback: DropBridgeClientKind = "canvascope_extension",
): DropBridgeClientKind {
  return value === "lectra_ipad"
    ? "lectra_ipad"
    : value === "canvascope_extension"
    ? "canvascope_extension"
    : fallback;
}

export function buildDropBridgeWakeTopic(userId: string, deviceId: string): string {
  return `dropbridge:user:${userId}:device:${deviceId}`;
}

export async function resolveMostRecentLectraDevice(userId: string): Promise<PushTarget | null> {
  const activeReceiverCutoff = new Date(Date.now() - ACTIVE_RECEIVER_WINDOW_MS).toISOString();

  let { data: device, error } = await admin
    .from("devices")
    .select("id, user_id, client_kind, push_token, push_environment, last_seen_at")
    .eq("user_id", userId)
    .eq("client_kind", "lectra_ipad")
    .is("revoked_at", null)
    .gt("last_seen_at", activeReceiverCutoff)
    .order("last_seen_at", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle<PushTarget>();

  if (error) {
    throw new Error(`Failed to load active Lectra device: ${error.message}`);
  }

  if (device) {
    return device;
  }

  const fallback = await admin
    .from("devices")
    .select("id, user_id, client_kind, push_token, push_environment, last_seen_at")
    .eq("user_id", userId)
    .eq("client_kind", "lectra_ipad")
    .is("revoked_at", null)
    .order("last_seen_at", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle<PushTarget>();

  if (fallback.error) {
    throw new Error(`Failed to load fallback Lectra device: ${fallback.error.message}`);
  }

  return fallback.data ?? null;
}

export async function broadcastWakeHint(params: {
  userId: string;
  deviceId: string;
  event: string;
  payload: Record<string, unknown>;
}): Promise<boolean> {
  const topic = buildDropBridgeWakeTopic(params.userId, params.deviceId);
  const channel = admin.channel(topic, {
    config: {
      private: true,
    },
  });

  try {
    const result = await channel.send({
      type: "broadcast",
      event: params.event,
      payload: params.payload,
    });
    return result === "ok";
  } catch {
    return false;
  } finally {
    try {
      await admin.removeChannel(channel);
    } catch {
      // Best effort cleanup for the ephemeral server-side channel.
    }
  }
}

export async function maybeSendLectraBackgroundPush(params: {
  userId: string;
  deviceId: string;
  syncedItemId?: string | null;
  reason?: string | null;
}): Promise<MaybePushResult> {
  const { data: device, error } = await admin
    .from("devices")
    .select("id, user_id, client_kind, push_token, push_environment")
    .eq("id", params.deviceId)
    .eq("user_id", params.userId)
    .is("revoked_at", null)
    .maybeSingle<PushTarget>();

  if (error) {
    throw new Error(`Failed to load push target: ${error.message}`);
  }

  if (!device) {
    return { attempted: false, reason: "device_not_found" };
  }

  if (device.client_kind !== "lectra_ipad") {
    return { attempted: false, reason: "not_lectra_ipad" };
  }

  if (!device.push_token) {
    return { attempted: false, reason: "push_token_missing" };
  }

  if (device.push_environment !== "sandbox" && device.push_environment !== "production") {
    return { attempted: false, reason: "push_environment_missing" };
  }

  const apnsConfig = getApnsConfig();
  if (!apnsConfig) {
    return { attempted: false, reason: "apns_env_missing" };
  }

  const { data: claimedSlot, error: claimError } = await admin.rpc(
    "dropbridge_claim_background_push_slot",
    {
      target_device_id: device.id,
      min_interval_seconds: APNS_MIN_PUSH_INTERVAL_SECONDS,
    },
  );

  if (claimError) {
    throw new Error(`Failed to claim background push slot: ${claimError.message}`);
  }

  if (claimedSlot !== true) {
    return { attempted: false, reason: "push_throttled" };
  }

  await sendApnsBackgroundPush({
    apnsConfig,
    pushToken: device.push_token,
    pushEnvironment: device.push_environment,
    syncedItemId: params.syncedItemId ?? null,
    reason: params.reason ?? "document_refresh",
    deviceId: device.id,
  });

  return { attempted: true, reason: "sent" };
}

async function sendApnsBackgroundPush(params: {
  apnsConfig: ApnsConfig;
  pushToken: string;
  pushEnvironment: PushEnvironment;
  syncedItemId: string | null;
  reason: string;
  deviceId: string;
}): Promise<void> {
  const jwt = await createApnsJwt(params.apnsConfig);
  const endpoint = APNS_ENDPOINTS[params.pushEnvironment];
  const response = await fetch(`${endpoint}/3/device/${encodeURIComponent(params.pushToken)}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": params.apnsConfig.topic,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-expiration": "0",
      "apns-collapse-id": `lectra-${params.deviceId}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        "content-available": 1,
      },
      dropbridge: {
        reason: params.reason,
        syncedItemId: params.syncedItemId,
        event: "document_refresh",
      },
    }),
  });

  if (response.ok) {
    return;
  }

  const failureText = (await response.text()).trim();
  throw new Error(`APNs delivery failed (${response.status}): ${failureText || response.statusText}`);
}

async function createApnsJwt(config: ApnsConfig): Promise<string> {
  const cacheKey = `${config.teamId}:${config.keyId}:${config.topic}`;
  const now = Date.now();
  if (apnsJwtCache && apnsJwtCache.cacheKey === cacheKey && apnsJwtCache.expiresAtMs > now + 60_000) {
    return apnsJwtCache.token;
  }

  const signingKey = await getApnsSigningKey(config.privateKeyPem);
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .sign(signingKey);

  apnsJwtCache = {
    token,
    expiresAtMs: now + APNS_JWT_TTL_MS,
    cacheKey,
  };
  return token;
}

async function getApnsSigningKey(privateKeyPem: string): Promise<KeyLike> {
  if (apnsSigningKeyCache?.pem === privateKeyPem) {
    return apnsSigningKeyCache.key;
  }

  const imported = await importPKCS8(privateKeyPem, "ES256");
  apnsSigningKeyCache = { pem: privateKeyPem, key: imported };
  return imported;
}

function getApnsConfig(): ApnsConfig | null {
  const keyId = String(Deno.env.get("APNS_KEY_ID") ?? "").trim();
  const teamId = String(Deno.env.get("APNS_TEAM_ID") ?? "").trim();
  const topic = String(Deno.env.get("APNS_TOPIC") ?? "").trim();
  const privateKeyRaw = String(Deno.env.get("APNS_PRIVATE_KEY_P8") ?? "").trim();

  if (!keyId || !teamId || !topic || !privateKeyRaw) {
    return null;
  }

  return {
    keyId,
    teamId,
    topic,
    privateKeyPem: normalizePrivateKeyPem(privateKeyRaw),
  };
}

function normalizePrivateKeyPem(value: string): string {
  return value.replace(/\\n/g, "\n");
}
