// Company user, role, and device management. Deploy to the customer's project.
// The service-role key stays in Supabase Edge Function secrets only.
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
async function issueOfflineTicket(userId: string, installationId: string, ownerId: string) {
  const privateJwk = JSON.parse(Deno.env.get("WORKSPACE_PRIVATE_JWK") || "null"), publicJwk = JSON.parse(Deno.env.get("WORKSPACE_PUBLIC_JWK") || "null");
  if (!privateJwk?.d || !publicJwk?.x || !publicJwk?.y) return null;
  const now = Math.floor(Date.now()/1000), payload = { sub:userId, deviceId:installationId, ownerId, role:"admin_offline", status:"active", iat:now, exp:now+7*24*60*60 };
  const head=b64url(new TextEncoder().encode(JSON.stringify({alg:"ES256",typ:"JWT"}))), data=b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const key=await crypto.subtle.importKey("jwk",privateJwk,{name:"ECDSA",namedCurve:"P-256"},false,["sign"]);
  const sig=new Uint8Array(await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"},key,new TextEncoder().encode(`${head}.${data}`)));
  return {token:`${head}.${data}.${b64url(sig)}`,publicKey:{kty:"EC",crv:"P-256",x:publicJwk.x,y:publicJwk.y,ext:true,key_ops:["verify"]}};
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
    const user = await auth.json(), body = await req.json();
    const db = async (path: string, init: RequestInit = {}) => {
      const res = await fetch(`${url}/rest/v1/${path}`, { ...init, headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", ...(init.headers || {}) } });
      const raw = await res.text(); let data; try { data = raw ? JSON.parse(raw) : null; } catch { data = raw; }
      if (!res.ok) throw new Error(typeof data === "object" ? (data?.message || data?.hint || "Database request failed") : String(data));
      return data;
    };
    const members = await db(`da_company_memberships?user_id=eq.${user.id}&active=eq.true&select=owner_id,role,permissions`);
    if (!members.length) return json({ error: "Company membership is inactive or missing" }, 403);
    const owner = members[0].owner_id;
    if (body.action === "device-check") {
      const installationId=String(body.installationId||"");
      if (!/^[0-9a-f-]{36}$/i.test(installationId)) return json({error:"Valid device ID required"},400);
      const [devices,companies]=await Promise.all([db(`da_company_devices?owner_id=eq.${owner}&installation_id=eq.${installationId}&user_id=eq.${user.id}&select=*`),db(`da_companies?owner_id=eq.${owner}&select=company_name,admin_device_id`)]);
      if (!devices.length || devices[0].status!=='active') return json({error:"This device is not active. Ask the Company Admin to approve it."},403);
      const device=devices[0], company=companies[0], isAdminDevice=company?.admin_device_id===installationId && device.device_role==='admin_offline' && members[0].role==='company_admin';
      const offlineTicket=isAdminDevice?await issueOfflineTicket(user.id,installationId,owner):null;
      return json({ownerId:owner,companyName:company?.company_name||"",role:members[0].role,permissions:members[0].permissions||{},deviceRole:isAdminDevice?"admin_offline":"user",deviceStatus:device.status,adminDeviceId:company?.admin_device_id||null,offlineTicket});
    }
    if (members[0].role !== "company_admin") return json({ error: "Company Admin access required" }, 403);

    if (body.action === "list") {
      const [users, devices, companies, conflicts] = await Promise.all([
        db(`da_company_memberships?owner_id=eq.${owner}&select=user_id,email,role,permissions,active,created_at&order=created_at.asc`),
        db(`da_company_devices?owner_id=eq.${owner}&select=installation_id,user_id,device_name,device_role,status,last_seen_at&order=last_seen_at.desc`),
        db(`da_companies?owner_id=eq.${owner}&select=owner_id,company_name,admin_device_id`),
        db(`da_attendance_conflicts?owner_id=eq.${owner}&resolution=eq.pending&select=resolution_id,attendance_key,local_record,server_record,resolved_by,resolved_at&order=resolved_at.asc`)
      ]);
      return json({ users, devices, company: companies[0] || null, conflicts });
    }
    if (body.action === "invite") {
      const email = String(body.email || "").trim().toLowerCase();
      const role = String(body.role || "attendance_operator");
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Enter a valid email address" }, 400);
      if (!["company_admin", "attendance_operator", "report_viewer"].includes(role)) return json({ error: "Choose a valid role" }, 400);
      const invite = await fetch(`${url}/auth/v1/invite`, { method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify({ email }) });
      const inviteData = await invite.json().catch(() => ({}));
      if (!invite.ok || !inviteData.id) return json({ error: inviteData.msg || inviteData.message || "Could not send invite. Check Auth email settings or whether this email already has an account." }, 400);
      const permissions = role === "company_admin" ? {} : role === "attendance_operator" ? { "employees.read": true, "attendance.write": true } : { "employees.read": true, "reports.read": true };
      await db("da_company_memberships", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ owner_id: owner, user_id: inviteData.id, email, role, permissions, active: true }) });
      return json({ ok: true, userId: inviteData.id, email, role });
    }
    if (body.action === "member-update") {
      const memberId = String(body.userId || "");
      const role = String(body.role || "");
      if (!/^[0-9a-f-]{36}$/i.test(memberId) || !["company_admin", "attendance_operator", "report_viewer"].includes(role)) return json({ error: "Invalid user or role" }, 400);
      const target=await db(`da_company_memberships?owner_id=eq.${owner}&user_id=eq.${memberId}&select=user_id,role,active`);
      if (!target.length) return json({error:"Company user not found"},404);
      if (target[0].role==='company_admin' && (role!=='company_admin' || body.active===false)) {
        const admins=await db(`da_company_memberships?owner_id=eq.${owner}&role=eq.company_admin&active=eq.true&select=user_id`);
        if (admins.length<=1) return json({error:"Keep at least one active Company Admin. Add another Admin before disabling this account."},409);
      }
      const permissions = role === "company_admin" ? {} : role === "attendance_operator" ? { "employees.read": true, "attendance.write": true } : { "employees.read": true, "reports.read": true };
      await db(`da_company_memberships?owner_id=eq.${owner}&user_id=eq.${memberId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ role, permissions, active: body.active !== false }) });
      return json({ ok: true });
    }
    if (body.action === "device-update") {
      const installationId = String(body.installationId || "");
      if (!/^[0-9a-f-]{36}$/i.test(installationId)) return json({ error: "Invalid device ID" }, 400);
      const status = body.status === "blocked" ? "blocked" : "active";
      await db(`da_company_devices?owner_id=eq.${owner}&installation_id=eq.${installationId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ status }) });
      return json({ ok: true });
    }
    if (body.action === "set-admin-device") {
      const installationId = String(body.installationId || "");
      if (!/^[0-9a-f-]{36}$/i.test(installationId)) return json({ error: "Invalid device ID" }, 400);
      const rows = await db(`da_company_devices?owner_id=eq.${owner}&installation_id=eq.${installationId}&select=installation_id`);
      if (!rows.length) return json({ error: "Device is not linked to this company" }, 404);
      const deviceUsers=await db(`da_company_devices?owner_id=eq.${owner}&installation_id=eq.${installationId}&select=user_id`),deviceMembers=await db(`da_company_memberships?owner_id=eq.${owner}&user_id=eq.${deviceUsers[0].user_id}&select=role,active`);
      if (!deviceMembers.length || deviceMembers[0].role!=='company_admin' || !deviceMembers[0].active) return json({error:"Only an active Company Admin device can be designated for offline attendance"},400);
      await db(`da_company_devices?owner_id=eq.${owner}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ device_role: "user" }) });
      await db(`da_company_devices?owner_id=eq.${owner}&installation_id=eq.${installationId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ device_role: "admin_offline" }) });
      await db(`da_companies?owner_id=eq.${owner}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ admin_device_id: installationId, updated_at: new Date().toISOString() }) });
      return json({ ok: true });
    }
    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Request failed" }, 400);
  }
});
