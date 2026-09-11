import type { Env } from "./types";
import { bad, json, nowIso, requireUser } from "./util";

export async function handleFiles(req: Request, env: Env, path: string): Promise<Response | null> {
  const match = path.match(/^\/files\/([^/]+)$/);
  if (!match) return null;
  const bookId = decodeURIComponent(match[1]);
  const user = await requireUser(req, env);
  if (user instanceof Response) return user;
  const key = `${user.sub}/${bookId}/content.txt`;

  if (req.method === "PUT") {
    const body = await req.arrayBuffer();
    if (body.byteLength === 0) return bad("空文件");
    if (body.byteLength > 40 * 1024 * 1024) return bad("文件过大（上限 40MB）", 413);
    await env.BOOKS.put(key, body, {
      httpMetadata: { contentType: "text/plain; charset=utf-8" },
    });
    const ts = nowIso();
    const existing = await env.DB.prepare(`SELECT payload FROM books WHERE user_id=? AND id=?`)
      .bind(user.sub, bookId)
      .first<{ payload: string }>();
    if (existing) {
      const payload = JSON.parse(existing.payload) as Record<string, unknown>;
      payload.r2Key = key;
      await env.DB.prepare(
        `UPDATE books SET payload=?, updated_at=?, r2_key=? WHERE user_id=? AND id=?`
      )
        .bind(JSON.stringify(payload), ts, key, user.sub, bookId)
        .run();
    } else {
      await env.DB.prepare(
        `INSERT INTO books(user_id, id, payload, updated_at, r2_key) VALUES(?, ?, ?, ?, ?)`
      )
        .bind(
          user.sub,
          bookId,
          JSON.stringify({ id: bookId, title: bookId, originRaw: "local", lastChapterIndex: 0, lastScrollOffset: 0, addedAt: ts, chapterCount: 0, r2Key: key }),
          ts,
          key
        )
        .run();
    }
    return json({ ok: true, key, updatedAt: ts });
  }

  if (req.method === "GET") {
    const obj = await env.BOOKS.get(key);
    if (!obj) return bad("文件不存在", 404);
    return new Response(obj.body, {
      headers: {
        "content-type": "text/plain; charset=utf-8",
        "access-control-allow-origin": "*",
      },
    });
  }

  return bad("Method Not Allowed", 405);
}
