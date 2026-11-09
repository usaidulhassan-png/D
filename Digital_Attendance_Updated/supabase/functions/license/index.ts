// Deploy separately with Supabase CLI. Store SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY as Edge Function secrets; never in PWA files.
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
async function issueTicket(userId: string, installationId: string, customerId: string, deviceId: string) {
  const privateJwk = JSON.parse(Deno.env.get("LICENSE_PRIVATE_JWK") || "null");
  const publicJwk = JSON.parse(Deno.env.get("LICENSE_PUBLIC_JWK") || "null");
  if (!privateJwk?.d || !publicJwk?.x || !publicJwk?.y) throw new Error("License signing keys are not configured");
  const now = Math.floor(Date.now() / 1000), payload = { sub: userId, deviceId: installationId, customerId, status: "active", iat: now, exp: now + 7 * 24 * 60 * 60 };
  const head = b64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", typ: "JWT" })));
  const body = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey("jwk", privateJwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${body}`)));
  return { token: `${head}.${body}.${b64url(signature)}`, publicKey: { kty: "EC", crv: "P-256", x: publicJwk.x, y: publicJwk.y, ext: true, key_ops: ["verify"] }, customerId };
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  try {
    if (req.method !== "POST") return json({ error: "POST required" }, 405);
    const url = Deno.env.get("SUPABASE_URL")!, key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const bearer = req.headers.get("Authorization") || "";
    const auth = await fetch(`${url}/auth/v1/user`, { headers: { apikey: key, Authorization: bearer } });
    if (!auth.ok) return json({ error: "Sign in required" }, 401);
    const user = await auth.json();
    const body = await req.json();
    const db = async (path: string, init: RequestInit = {}) => {
      const response = await fetch(`${url}/rest/v1/${path}`, { ...init, headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", ...(init.headers || {}) } });
      const value = await response.text();
      if (!response.ok) throw new Error(value || `Database request failed (${response.status})`);
      return value ? JSON.parse(value) : null;
    };
    const event = async (customer: string | null, device: string | null, type: string, detail = {}) => db("da_license_events", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ customer_id: customer, device_id: device, event_type: type, detail }) });
    const findCustomer = async () => (await db(`da_license_customers?auth_user_id=eq.${user.id}&select=*`))[0] || null;
    const ensureOwner = async () => {
      const rows = await db(`da_license_owner_accounts?auth_user_id=eq.${user.id}&select=auth_user_id`);
      if (!rows.length) throw new Error("Owner access required");
    };

    if (body.action === "restore-request") {
      if (typeof body.installationId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.installationId)) return json({ error: "Valid installation ID required" }, 400);
      const customer = await findCustomer();
      if (!customer || typeof body.backupCustomerId !== "string" || body.backupCustomerId !== customer.serial_id) return json({ error: "This backup is not linked to the signed-in customer account" }, 403);
      if (customer.status !== "active") return json({ error: "Customer license is not active" }, 403);
      let device = (await db("da_license_devices?customer_id=eq." + customer.id + "&installation_id=eq." + body.installationId + "&select=*"))[0] || null;
      if (!device) {
        device = (await db("da_license_devices", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ customer_id: customer.id, installation_id: body.installationId, status: "pending" }) }))[0];
        await event(customer.id, device.id, "restore_device_approval_requested", { backup_device_id: body.backupDeviceId || null });
      }
      if (customer.status === "active" && device.status === "active") {
        const ticket = await issueTicket(user.id, body.installationId, customer.serial_id, device.id);
        return json({ ...ticket, customerStatus: customer.status, deviceId: device.id, deviceStatus: device.status, approvalRequired: false, offlineDays: 7 });
      }
      return json({ customerId: customer.serial_id, customerStatus: customer.status, deviceId: device.id, deviceStatus: device.status, approvalRequired: true });
    }

    if (body.action === "register-device" || body.action === "verify") {
      if (typeof body.installationId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.installationId)) return json({ error: "Valid installation ID required" }, 400);
      let customer = await findCustomer();
      if (!customer && body.action === "register-device") {
        const serial = await db("rpc/da_next_customer_serial", { method: "POST", body: "{}" });
        customer = (await db("da_license_customers", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ auth_user_id: user.id, serial_id: serial, status: "pending" }) }))[0];
      }
      if (!customer) return json({ error: "Customer license is not registered" }, 404);
      let device = (await db(`da_license_devices?customer_id=eq.${customer.id}&installation_id=eq.${body.installationId}&select=*`))[0] || null;
      if (!device && body.action === "register-device") {
        const first = !(await db(`da_license_devices?customer_id=eq.${customer.id}&select=id&limit=1`)).length;
        device = (await db("da_license_devices", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ customer_id: customer.id, installation_id: body.installationId, status: first && customer.status === "active" ? "active" : "pending", approved_at: first && customer.status === "active" ? new Date().toISOString() : null }) }))[0];
        await event(customer.id, device.id, first && customer.status === "active" ? "device_registered" : "device_pending_approval");
      }
      if (!device) return json({ error: "This installation needs owner approval" }, 403);
      await db(`da_license_devices?id=eq.${device.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ last_verified_at: new Date().toISOString(), last_activity_at: new Date().toISOString() }) });
      await db(`da_license_customers?id=eq.${customer.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ last_verified_at: new Date().toISOString() }) });
      if (customer.status !== "active" || device.status !== "active") return json({ error: "Customer or device is not active; owner approval is required" }, 403);
      await event(customer.id, device.id, "license_checked");
      const ticket = await issueTicket(user.id, body.installationId, customer.serial_id, device.id);
      return json({ ...ticket, customerStatus: customer.status, deviceId: device.id, deviceStatus: device.status, offlineDays: 7, verifiedAt: new Date().toISOString() });
    }

    await ensureOwner();
    if (body.action === "owner-list") {
      const [customers, devices] = await Promise.all([db("da_license_customers?select=*&order=created_at.desc"), db("da_license_devices?select=*&order=last_activity_at.desc.nullslast")]);
      return json({ customers, devices });
    }
    if (body.action === "owner-customer-status" && typeof body.customerId === "string" && ["active", "inactive", "blocked"].includes(body.status)) {
      await db(`da_license_customers?id=eq.${body.customerId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ status: body.status, updated_at: new Date().toISOString() }) });
      await event(body.customerId, null, "customer_status_changed", { status: body.status });
      return json({ ok: true });
    }
    if (["owner-device-status", "approve-device"].includes(body.action) && typeof body.deviceId === "string") {
      const status = body.action === "approve-device" ? "active" : body.status;
      if (!["active", "inactive", "blocked"].includes(status)) return json({ error: "Invalid device status" }, 400);
      const rows = await db(`da_license_devices?id=eq.${body.deviceId}&select=customer_id`);
      if (!rows.length) return json({ error: "Device not found" }, 404);
      await db(`da_license_devices?id=eq.${body.deviceId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ status, approved_at: status === "active" ? new Date().toISOString() : null }) });
      await event(rows[0].customer_id, body.deviceId, "device_status_changed", { status });
      return json({ ok: true });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request failed";
    return json({ error: message }, message.includes("Owner access") ? 403 : 400);
  }
});
