import type { Env } from "./types";
import { bad, json, newId, nowIso, randomCode, requireUser, signJwt } from "./util";

export async function handleAuth(req: Request, env: Env, path: string): Promise<Response | null> {
  if (path === "/auth/request-otp" && req.method === "POST") {
    const body = (await req.json().catch(() => null)) as { email?: string } | null;
    const email = (body?.email || "").trim().toLowerCase();
    if (!email || !email.includes("@")) return bad("邮箱无效");
    const code = randomCode();
    const expires = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    await env.DB.prepare(
      `INSERT INTO otps(email, code, expires_at) VALUES(?, ?, ?)
       ON CONFLICT(email) DO UPDATE SET code=excluded.code, expires_at=excluded.expires_at`
    )
      .bind(email, code, expires)
      .run();

    const echo = (env.OTP_ECHO || "").toLowerCase() === "true";
    // Production: send email via Resend/MailChannels. Dev: echo code.
    return json({
      ok: true,
      message: echo ? "开发模式：验证码已回显" : "验证码已发送（若已配置邮件通道）",
      ...(echo ? { echoCode: code } : {}),
    });
  }

  if (path === "/auth/verify" && req.method === "POST") {
    const body = (await req.json().catch(() => null)) as { email?: string; code?: string } | null;
    const email = (body?.email || "").trim().toLowerCase();
    const code = (body?.code || "").trim();
    if (!email || !code) return bad("参数不完整");

    const row = await env.DB.prepare(`SELECT code, expires_at FROM otps WHERE email=?`)
      .bind(email)
      .first<{ code: string; expires_at: string }>();
    if (!row || row.code !== code) return bad("验证码错误", 401);
    if (new Date(row.expires_at).getTime() < Date.now()) return bad("验证码已过期", 401);

    await env.DB.prepare(`DELETE FROM otps WHERE email=?`).bind(email).run();

    const existing = await env.DB.prepare(`SELECT id FROM users WHERE email=?`)
      .bind(email)
      .first<{ id: string }>();
    const userId = existing?.id || newId();
    const ts = nowIso();
    if (!existing) {
      await env.DB.prepare(
        `INSERT INTO users(id, email, created_at, updated_at) VALUES(?, ?, ?, ?)`
      )
        .bind(userId, email, ts, ts)
        .run();
    } else {
      await env.DB.prepare(`UPDATE users SET updated_at=? WHERE id=?`).bind(ts, userId).run();
    }

    const secret = env.JWT_SECRET || "dev-inkshelf-secret-change-me";
    const token = await signJwt(
      { sub: userId, email, exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30 },
      secret
    );
    return json({ ok: true, token, user: { id: userId, email } });
  }

  if (path === "/auth/me" && req.method === "GET") {
    const user = await requireUser(req, env);
    if (user instanceof Response) return user;
    return json({ ok: true, user: { id: user.sub, email: user.email } });
  }

  return null;
}
