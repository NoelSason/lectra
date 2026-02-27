import { corsHeaders, json } from "../_shared/cors.ts";
import { admin, sanitizeFileName } from "../_shared/device-auth.ts";
import { HttpError, requireAuthUser } from "../_shared/auth-user.ts";

const MAX_FILE_BYTES = 25 * 1024 * 1024;
const QUEUE_RETENTION_MS = 24 * 60 * 60 * 1000;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireAuthUser(request);
    const formData = await request.formData();
    const file = formData.get("file");

    if (!(file instanceof File)) {
      return json({ error: "Missing file field" }, 400);
    }

    if (file.size <= 0) {
      return json({ error: "File is empty" }, 400);
    }

    if (file.size > MAX_FILE_BYTES) {
      return json({ error: `File exceeds ${MAX_FILE_BYTES} byte limit` }, 413);
    }

    const { data: receiver, error: receiverError } = await admin
      .from("devices")
      .select("id, last_seen_at")
      .eq("user_id", user.id)
      .eq("client_kind", "canvascope_extension")
      .is("revoked_at", null)
      .order("last_seen_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();

    if (receiverError) {
      throw new Error(`Receiver lookup failed: ${receiverError.message}`);
    }

    if (!receiver) {
      return json(
        {
          error: "No active Canvascope receiver found. Open the Canvascope extension and try again.",
        },
        404,
      );
    }

    const uploadId = crypto.randomUUID();
    const fileName = sanitizeFileName(file.name || "upload.bin");
    const objectPath = `${user.id}/${receiver.id}/${uploadId}-${fileName}`;
    const contentType = file.type || "application/octet-stream";
    const expiresAt = new Date(Date.now() + QUEUE_RETENTION_MS).toISOString();
    const arrayBuffer = await file.arrayBuffer();

    const { error: storageError } = await admin.storage.from("drops").upload(objectPath, arrayBuffer, {
      contentType,
      upsert: false,
    });

    if (storageError) {
      throw new Error(`Storage upload failed: ${storageError.message}`);
    }

    const { error: rowError } = await admin.from("uploads").insert({
      id: uploadId,
      user_id: user.id,
      device_id: receiver.id,
      file_name: fileName,
      object_path: objectPath,
      mime_type: contentType,
      size_bytes: file.size,
      status: "queued",
      expires_at: expiresAt,
    });

    if (rowError) {
      await admin.storage.from("drops").remove([objectPath]);
      throw new Error(`Failed to record upload metadata: ${rowError.message}`);
    }

    return json({
      ok: true,
      uploadId,
      fileName,
      sizeBytes: file.size,
      contentType,
      receiverId: receiver.id,
      expiresAt,
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
