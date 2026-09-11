export interface Env {
  DB: D1Database;
  BOOKS: R2Bucket;
  JWT_SECRET: string;
  OTP_ECHO?: string;
}

export type JwtPayload = {
  sub: string;
  email: string;
  exp: number;
};

export type SyncBookPayload = {
  id: string;
  title: string;
  author?: string | null;
  originRaw: string;
  sourceId?: string | null;
  sourceName?: string | null;
  bookUrl?: string | null;
  coverUrl?: string | null;
  intro?: string | null;
  lastChapterIndex: number;
  lastScrollOffset: number;
  lastReadAt?: string | null;
  addedAt: string;
  chapterCount: number;
  r2Key?: string | null;
  chapters?: { index: number; title: string; remoteUrl?: string | null }[] | null;
};

export type SyncBookmarkPayload = {
  id: string;
  bookId: string;
  chapterIndex: number;
  title: string;
  scrollOffset: number;
  createdAt: string;
};

export type SyncSourcePayload = {
  id: string;
  name: string;
  sourceUrl: string;
  enabled: boolean;
  legadoRaw: string;
  groupName?: string | null;
  addedAt: string;
};

export type SyncPrefsPayload = {
  readMode: string;
  fontSize: number;
  lineHeight: number;
  themeMode: string;
  autoReadEnabled: boolean;
  autoReadSpeed: number;
  followSystemBrightness: boolean;
  brightness: number;
};

export type SyncItem<T> = {
  id: string;
  updatedAt: string;
  payload: T;
};
