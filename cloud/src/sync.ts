import type {
  Env,
  SyncBookmarkPayload,
  SyncBookPayload,
  SyncItem,
  SyncPrefsPayload,
  SyncSourcePayload,
} from "./types";
import { bad, json, nowIso, requireUser } from "./util";

type PushBody = {
  books?: SyncItem<SyncBookPayload>[];
  bookmarks?: SyncItem<SyncBookmarkPayload>[];
  sources?: SyncItem<SyncSourcePayload>[];
  prefs?: SyncItem<SyncPrefsPayload> | null;
};

export async function handleSync(req: Request, env: Env, path: string): Promise<Response | null> {
  if (path === "/sync/pull" && req.method === "GET") {
    const user = await requireUser(req, env);
    if (user instanceof Response) return user;
    const url = new URL(req.url);
    const sinceRaw = url.searchParams.get("since") || "1970-01-01T00:00:00.000Z";
    const since = sinceRaw === "0" ? "1970-01-01T00:00:00.000Z" : sinceRaw;

    const books = await env.DB.prepare(
      `SELECT id, payload, updated_at, r2_key FROM books WHERE user_id=? AND updated_at>?`
    )
      .bind(user.sub, since)
      .all<{ id: string; payload: string; updated_at: string; r2_key: string | null }>();

    const bookmarks = await env.DB.prepare(
      `SELECT id, book_id, payload, updated_at FROM bookmarks WHERE user_id=? AND updated_at>?`
    )
      .bind(user.sub, since)
      .all<{ id: string; book_id: string; payload: string; updated_at: string }>();

    const sources = await env.DB.prepare(
      `SELECT id, payload, updated_at FROM sources WHERE user_id=? AND updated_at>?`
    )
      .bind(user.sub, since)
      .all<{ id: string; payload: string; updated_at: string }>();

    const prefs = await env.DB.prepare(
      `SELECT payload, updated_at FROM prefs WHERE user_id=? AND updated_at>?`
    )
      .bind(user.sub, since)
      .first<{ payload: string; updated_at: string }>();

    return json({
      ok: true,
      serverTime: nowIso(),
      books: (books.results || []).map((r) => ({
        id: r.id,
        updatedAt: r.updated_at,
        payload: { ...(JSON.parse(r.payload) as SyncBookPayload), r2Key: r.r2_key },
      })),
      bookmarks: (bookmarks.results || []).map((r) => ({
        id: r.id,
        updatedAt: r.updated_at,
        payload: JSON.parse(r.payload) as SyncBookmarkPayload,
      })),
      sources: (sources.results || []).map((r) => ({
        id: r.id,
        updatedAt: r.updated_at,
        payload: JSON.parse(r.payload) as SyncSourcePayload,
      })),
      prefs: prefs
        ? { id: "prefs", updatedAt: prefs.updated_at, payload: JSON.parse(prefs.payload) as SyncPrefsPayload }
        : null,
    });
  }

  if (path === "/sync/push" && req.method === "POST") {
    const user = await requireUser(req, env);
    if (user instanceof Response) return user;
    const body = (await req.json().catch(() => null)) as PushBody | null;
    if (!body) return bad("无效 JSON");

    let accepted = 0;

    for (const item of body.books || []) {
      if (!item?.id || !item.updatedAt || !item.payload) continue;
      const existing = await env.DB.prepare(
        `SELECT updated_at FROM books WHERE user_id=? AND id=?`
      )
        .bind(user.sub, item.id)
        .first<{ updated_at: string }>();
      if (existing && existing.updated_at >= item.updatedAt) continue;
      const r2Key = item.payload.r2Key || null;
      await env.DB.prepare(
        `INSERT INTO books(user_id, id, payload, updated_at, r2_key) VALUES(?, ?, ?, ?, ?)
         ON CONFLICT(user_id, id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at, r2_key=excluded.r2_key`
      )
        .bind(user.sub, item.id, JSON.stringify(item.payload), item.updatedAt, r2Key)
        .run();
      accepted += 1;
    }

    for (const item of body.bookmarks || []) {
      if (!item?.id || !item.updatedAt || !item.payload) continue;
      const existing = await env.DB.prepare(
        `SELECT updated_at FROM bookmarks WHERE user_id=? AND id=?`
      )
        .bind(user.sub, item.id)
        .first<{ updated_at: string }>();
      if (existing && existing.updated_at >= item.updatedAt) continue;
      await env.DB.prepare(
        `INSERT INTO bookmarks(user_id, id, book_id, payload, updated_at) VALUES(?, ?, ?, ?, ?)
         ON CONFLICT(user_id, id) DO UPDATE SET book_id=excluded.book_id, payload=excluded.payload, updated_at=excluded.updated_at`
      )
        .bind(user.sub, item.id, item.payload.bookId, JSON.stringify(item.payload), item.updatedAt)
        .run();
      accepted += 1;
    }

    for (const item of body.sources || []) {
      if (!item?.id || !item.updatedAt || !item.payload) continue;
      const existing = await env.DB.prepare(
        `SELECT updated_at FROM sources WHERE user_id=? AND id=?`
      )
        .bind(user.sub, item.id)
        .first<{ updated_at: string }>();
      if (existing && existing.updated_at >= item.updatedAt) continue;
      await env.DB.prepare(
        `INSERT INTO sources(user_id, id, payload, updated_at) VALUES(?, ?, ?, ?)
         ON CONFLICT(user_id, id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at`
      )
        .bind(user.sub, item.id, JSON.stringify(item.payload), item.updatedAt)
        .run();
      accepted += 1;
    }

    if (body.prefs?.payload && body.prefs.updatedAt) {
      const existing = await env.DB.prepare(`SELECT updated_at FROM prefs WHERE user_id=?`)
        .bind(user.sub)
        .first<{ updated_at: string }>();
      if (!existing || existing.updated_at < body.prefs.updatedAt) {
        await env.DB.prepare(
          `INSERT INTO prefs(user_id, payload, updated_at) VALUES(?, ?, ?)
           ON CONFLICT(user_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at`
        )
          .bind(user.sub, JSON.stringify(body.prefs.payload), body.prefs.updatedAt)
          .run();
        accepted += 1;
      }
    }

    return json({ ok: true, accepted, serverTime: nowIso() });
  }

  return null;
}
