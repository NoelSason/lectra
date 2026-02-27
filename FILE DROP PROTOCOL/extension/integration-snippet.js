// Minimal contract helpers for existing extension integration.

export async function callDropBridgeFunction({ supabaseUrl, anonKey, functionName, body }) {
  const url = `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/${functionName}`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
    },
    body: JSON.stringify(body),
  });

  const json = await response.json().catch(() => ({}));
  if (!response.ok || json.error) {
    throw new Error(json.error || `DropBridge ${functionName} failed (${response.status})`);
  }

  return json;
}

export function isUserCanceled(errorText) {
  const v = String(errorText || "").toUpperCase();
  return v.includes("USER_CANCELED") || v.includes("CANCELED");
}
