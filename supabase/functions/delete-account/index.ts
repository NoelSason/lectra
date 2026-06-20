// Supabase Edge Function: delete-account
//
// Permanently deletes the authenticated user's Lectra account and all of
// their server-side data. Required by App Review Guideline 5.1.1(v) (in-app
// account deletion).
//
// The iOS client invokes this with the signed-in user's JWT (the Supabase SDK
// attaches it automatically). We verify that JWT to identify the caller, then
// use the service-role key to perform the destructive work. The service-role
// key NEVER ships in the app — it only exists in the Edge Function environment.
//
// Deploy:
//   supabase functions deploy delete-account --project-ref vcadcdgnwxjlgaoqktkd
//
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically by the Supabase runtime; no extra secrets needed.

import { createClient } from "jsr:@supabase/supabase-js@2";

const STORAGE_BUCKET = "lectra_documents";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  if (
    typeof error === "object" &&
    error !== null &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error.message;
  }
  return "Unknown error";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization header." }, 401);
  }

  let supabaseUrl: string;
  let anonKey: string;
  let serviceRoleKey: string;
  try {
    supabaseUrl = requiredEnv("SUPABASE_URL");
    anonKey = requiredEnv("SUPABASE_ANON_KEY");
    serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  } catch (error) {
    return json(
      { error: `Server configuration error: ${errorMessage(error)}` },
      500,
    );
  }

  let userId: string;
  try {
    // 1. Identify the caller from their JWT (anon client scoped to their token).
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await callerClient.auth.getUser();

    if (userError || !user) {
      return json({ error: "Invalid or expired session." }, 401);
    }

    userId = user.id;
  } catch (error) {
    return json({
      error: `Account authorization failed: ${errorMessage(error)}`,
    }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    // 2. Collect the exact storage paths recorded in the user's rows.
    const { data: rows, error: rowsError } = await admin
      .from("synced_items")
      .select("item_data")
      .eq("user_id", userId);
    if (rowsError) {
      return json({
        error: `Failed to load account data: ${rowsError.message}`,
      }, 500);
    }

    const storagePaths = new Set<string>();
    for (const row of rows ?? []) {
      const itemData =
        (row as { item_data?: Record<string, unknown> }).item_data;
      const candidates = [
        itemData?.storagePath,
        itemData?.annotatedStoragePath,
      ];
      for (const candidate of candidates) {
        if (typeof candidate === "string" && candidate.length > 0) {
          storagePaths.add(candidate);
        }
      }
    }

    // 3. Safety net: recursively walk the user's storage prefix.
    async function collectPrefix(prefix: string) {
      const { data: entries, error: listError } = await admin.storage
        .from(STORAGE_BUCKET)
        .list(prefix, { limit: 1000 });
      if (listError) {
        throw new Error(
          `Failed to list storage prefix ${prefix}: ${listError.message}`,
        );
      }
      for (const entry of entries ?? []) {
        const path = prefix ? `${prefix}/${entry.name}` : entry.name;
        // Folders have a null id in the Storage list response.
        if ((entry as { id: string | null }).id === null) {
          await collectPrefix(path);
        } else {
          storagePaths.add(path);
        }
      }
    }
    await collectPrefix(userId);

    if (storagePaths.size > 0) {
      const { error: removeError } = await admin.storage
        .from(STORAGE_BUCKET)
        .remove([...storagePaths]);
      if (removeError) {
        return json({
          error: `Failed to remove storage objects: ${removeError.message}`,
        }, 500);
      }
    }

    // 4. Delete the user's database rows.
    const { error: rowsDeleteError } = await admin
      .from("synced_items")
      .delete()
      .eq("user_id", userId);
    if (rowsDeleteError) {
      return json({
        error: `Failed to delete synced documents: ${rowsDeleteError.message}`,
      }, 500);
    }

    // 5. Best-effort cleanup of push-device registrations (table may not exist).
    const { error: devicesError } = await admin
      .from("lectra_devices")
      .delete()
      .eq("user_id", userId);
    if (devicesError) {
      // Ignore — device rows also clear when the auth user is removed if a
      // foreign key with ON DELETE CASCADE is configured, and older backends
      // may not have this optional table yet.
    }

    // 6. Delete the auth user itself.
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      return json(
        { error: `Failed to delete account: ${deleteError.message}` },
        500,
      );
    }

    return json({ success: true });
  } catch (error) {
    return json(
      { error: `Account deletion failed: ${errorMessage(error)}` },
      500,
    );
  }
});
