import { REGIONAL_LEARNING_ACTIONS, regionalLearningReplaySafe } from "./learning-regional-actions.ts";
const LEARNING_ACTIONS = new Set<string>(REGIONAL_LEARNING_ACTIONS);

// Supabase's documented Edge regions. Unknown/local runtime values fail closed
// to the original handler instead of accidentally starting a relay loop.
const EDGE_REGIONS = new Set([
  "ap-northeast-1", "ap-northeast-2", "ap-south-1", "ap-southeast-1", "ap-southeast-2",
  "ca-central-1", "us-east-1", "us-west-1", "us-west-2", "eu-central-1", "eu-central-2",
  "eu-west-1", "eu-west-2", "eu-west-3", "sa-east-1",
]);

export interface JuniorRegionalRelayConfig {
  /** Trusted deployment SUPABASE_URL only; never derive this from request input. */
  supabaseUrl: string;
  currentRegion?: string;
  targetRegion?: string;
  /** Original request text, when the caller already consumed it to parse action. */
  rawBody?: string;
  fetch?: typeof fetch;
}

function isPrivilegedApiKey(value: string | null): boolean {
  if (!value) return false;
  if (value.startsWith("sb_secret_")) return true;
  const parts = value.split(".");
  if (parts.length !== 3) return false;
  try {
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload.padEnd(Math.ceil(payload.length / 4) * 4, "="))).role === "service_role";
  } catch { return false; }
}

/**
 * Single-hop transport only. A session header is NOT authentication: the target
 * must run its original session/ownership/source gates, and a null return means
 * the caller must run those same local gates. This helper never reads a service
 * role key or creates/approves a learning session itself.
 */
export async function relayJuniorRequest(
  request: Request,
  action: unknown,
  config: JuniorRegionalRelayConfig,
): Promise<Response | null> {
  const targetRegion = config.targetRegion ?? "ap-southeast-2";
  if (request.method !== "POST" || typeof action !== "string" || !LEARNING_ACTIONS.has(action)
    || !request.headers.get("x-app-session")?.trim()
    || !EDGE_REGIONS.has(config.currentRegion ?? "") || !EDGE_REGIONS.has(targetRegion)
    || config.currentRegion === targetRegion || request.headers.has("x-chem-region-relay")
    || isPrivilegedApiKey(request.headers.get("apikey"))) return null;

  let destination: URL;
  try {
    const project = new URL(config.supabaseUrl);
    const incoming = new URL(request.url);
    if (project.protocol !== "https:" || !/^[a-z0-9]{20}\.supabase\.co$/.test(project.hostname)
      || project.port || project.username || project.password || project.pathname !== "/"
      || project.search || project.hash) return null;
    // Edge ingress may rewrite request.url to an internal proxy origin. It is
    // not an identity or destination trust signal: only the deployment-owned
    // project above selects the target, never Host/Origin/path/query from req.
    if (incoming.searchParams.has("chemRegionalFallback") || incoming.searchParams.has("chemRegionRelay")) return null;
    // An explicit caller-selected region (including "any") is a deliberate
    // fallback/diagnostic choice. Never redirect it back to the failed region.
    if (incoming.searchParams.getAll("forceFunctionRegion").some((region) => region !== targetRegion)) return null;
    destination = new URL("/functions/v1/chemistry-access", project);
    destination.searchParams.set("forceFunctionRegion", targetRegion);
    destination.searchParams.set("chemRegionRelay", "1");
  } catch { return null; }

  const headers = new Headers();
  for (const key of ["content-type", "apikey", "x-app-session", "origin", "accept", "x-client-info"]) {
    const value = request.headers.get(key);
    if (value !== null) headers.set(key, value);
  }
  headers.set("X-Chem-Region-Relay", "1");
  request.signal.throwIfAborted();
  let body: string | ArrayBuffer;
  try {
    // Clone leaves the local fallback's request unread; do not stringify a
    // parsed answer or change its step/revision/option/duration on the retry.
    body = config.rawBody ?? await request.clone().arrayBuffer();
  } catch {
    request.signal.throwIfAborted();
    return null;
  }
  try {
    const response = await (config.fetch ?? fetch)(destination, {
      method: "POST", headers, body, signal: request.signal, redirect: "error",
    });
    if (response.status >= 500 && response.status <= 599) {
      if (!regionalLearningReplaySafe(action)) return response;
      void response.body?.cancel().catch(() => {});
      return null;
    }
    // Return the untouched stream, including authentication/permission/rate
    // errors. No local retry on 4xx, and no answer body parsing or buffering.
    return response;
  } catch (error) {
    request.signal.throwIfAborted();
    if (!regionalLearningReplaySafe(action)) throw error;
    return null;
  }
}
