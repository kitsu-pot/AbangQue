export type Session = {
  user: { id: string; email: string; role: "ADMIN" };
  expiresAt: string;
};
export type Activity = {
  id: string;
  name: string;
  source: "device" | "demo" | "simulated";
  active?: boolean;
  route: string | null;
  timestamp: string | null;
  lastSeenAt: string | null;
  freshness: "FRESH" | "STALE" | "MISSING";
  status: "FULL" | "AVAILABLE" | "UNKNOWN";
};
export type Dashboard = {
  updatedAt: string;
  staleAfterSeconds: number;
  summary: {
    jeepneys: number;
    routes: number;
    devices: number | null;
    demoJeepneys: number;
    fresh: number;
    staleOrMissing: number;
    full: number;
    available: number;
    validUntil: string | null;
  };
  recent: Activity[];
};
export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public code = "",
    public fields: { field: string; message: string }[] = [],
  ) {
    super(message);
  }
}
const origin = import.meta.env.VITE_ADMIN_API_ORIGIN || "";
if (origin) {
  const url = new URL(origin);
  if (url.origin !== origin || url.protocol !== "https:")
    throw new Error("Admin API origin must be an HTTPS origin");
}
export async function api<T>(
  path: string,
  body?: object,
  method: "POST" | "PUT" = "POST",
  signal?: AbortSignal,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(origin + "/api/admin" + path, {
      method: body ? method : "GET",
      credentials: "include",
      cache: "no-store",
      redirect: "error",
      signal: signal
        ? AbortSignal.any([signal, AbortSignal.timeout(10000)])
        : AbortSignal.timeout(10000),
      headers: body
        ? { "Content-Type": "application/json", "X-AbangQue-Admin": "1" }
        : {},
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError(
      0,
      "Unable to reach the server. Check your connection and try again.",
    );
  }
  if (!response.ok) {
    const failure = await response.json().catch(() => ({}));
    throw new ApiError(
      response.status,
      response.status === 429
        ? "Too many attempts. Please wait 15 minutes before trying again."
        : response.status === 401
          ? "Your session has ended. Please sign in again."
          : "The server could not complete this request. Please try again.",
      typeof failure.error === "string" ? failure.error : "",
      Array.isArray(failure.fields) ? failure.fields : [],
    );
  }
  if (response.status === 204) return undefined as T;
  try {
    return (await response.json()).data as T;
  } catch {
    throw new ApiError(
      0,
      "The server returned an unreadable response. Please retry.",
    );
  }
}
