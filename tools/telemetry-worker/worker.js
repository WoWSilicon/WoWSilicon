const CONFIG = {
  telemetry_enabled: true,
  heartbeat_enabled: false,
  heartbeat_interval_minutes: 60,
  launch_sample_rate: 1.0,
  heartbeat_sample_rate: 0.0,
  config_ttl_hours: 24,
  min_supported_telemetry_schema: 1,
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

const MAX_BODY_BYTES = 4096;
const ACTIVE_WINDOW_SECONDS = 30 * 60;
const HEARTBEAT_DEDUPE_SECONDS = 15 * 60;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method === "GET" && url.pathname === "/config.json") {
      return json(CONFIG, {
        "Cache-Control": `public, max-age=${CONFIG.config_ttl_hours * 60 * 60}`,
      });
    }

    if (request.method === "GET" && url.pathname === "/stats.json") {
      return json(await getStats(env.DB));
    }

    if (request.method === "POST" && url.pathname === "/event") {
      return handleEvent(request, env.DB);
    }

    return json({ error: "not_found" }, {}, 404);
  },
};

async function handleEvent(request, db) {
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength > MAX_BODY_BYTES) {
    return json({ error: "body_too_large" }, {}, 413);
  }

  let input;
  try {
    input = await request.json();
  } catch {
    return json({ error: "invalid_json" }, {}, 400);
  }

  const event = sanitizeEnum(input.event, ["launch", "wow_start", "heartbeat"]);
  const installId = sanitizeId(input.install_id);
  const sessionId = sanitizeId(input.session_id || input.install_id);

  if (!CONFIG.telemetry_enabled) {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (!event || !installId) {
    return json({ error: "invalid_event" }, {}, 400);
  }

  if (event === "heartbeat" && !CONFIG.heartbeat_enabled) {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const now = Math.floor(Date.now() / 1000);
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  const dimensions = normalizedDimensions(input);

  await db.prepare(
    `INSERT INTO installs (install_id, first_seen_at, last_seen_at)
     VALUES (?, ?, ?)
     ON CONFLICT(install_id) DO UPDATE SET last_seen_at = excluded.last_seen_at`
  ).bind(installId, now, now).run();

  if (event === "heartbeat") {
    const current = await db.prepare(
      "SELECT last_seen_at FROM active_sessions WHERE session_id = ?"
    ).bind(sessionId).first();

    if (current && now - current.last_seen_at < HEARTBEAT_DEDUPE_SECONDS) {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
  }

  await db.prepare(
    `INSERT OR IGNORE INTO daily_event_installs (day, event, install_id)
     VALUES (?, ?, ?)`
  ).bind(day, event, installId).run();

  for (const [dimension, value] of Object.entries(dimensions)) {
    if (value) {
      await db.prepare(
        `INSERT OR IGNORE INTO daily_dimension_installs (day, dimension, value, install_id)
         VALUES (?, ?, ?, ?)`
      ).bind(day, dimension, value, installId).run();
    }
  }

  if (event === "wow_start" || event === "heartbeat") {
    await db.prepare(
      `INSERT INTO active_sessions
         (session_id, install_id, last_seen_at, app_version, wow_version, renderer, macos_version, realmlist)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(session_id) DO UPDATE SET
         last_seen_at = excluded.last_seen_at,
         app_version = excluded.app_version,
         wow_version = excluded.wow_version,
         renderer = excluded.renderer,
         macos_version = excluded.macos_version,
         realmlist = excluded.realmlist`
    ).bind(
      sessionId,
      installId,
      now,
      dimensions.app_version,
      dimensions.wow_version,
      dimensions.renderer,
      dimensions.macos_version,
      dimensions.realmlist
    ).run();
  }

  return new Response(null, {
    status: 204,
    headers: {
      ...CORS_HEADERS,
      "Cache-Control": "no-store",
    },
  });
}

async function getStats(db) {
  const now = Math.floor(Date.now() / 1000);
  const activeSince = now - ACTIVE_WINDOW_SECONDS;
  const today = new Date(now * 1000).toISOString().slice(0, 10);
  const monthStart = today.slice(0, 7) + "-01";

  const totals = await db.prepare(
    `SELECT event, COUNT(*) AS count
     FROM daily_event_installs
     GROUP BY event`
  ).all();

  const todayTotals = await db.prepare(
    `SELECT event, COUNT(*) AS count
     FROM daily_event_installs
     WHERE day = ?
     GROUP BY event`
  ).bind(today).all();

  const monthTotals = await db.prepare(
    `SELECT event, COUNT(DISTINCT install_id) AS count
     FROM daily_event_installs
     WHERE day >= ?
     GROUP BY event`
  ).bind(monthStart).all();

  const dimensions = await db.prepare(
    `SELECT dimension, value, COUNT(*) AS count
     FROM daily_dimension_installs
     GROUP BY dimension, value
     ORDER BY count DESC
     LIMIT 200`
  ).all();

  const todayDimensions = await db.prepare(
    `SELECT dimension, value, COUNT(*) AS count
     FROM daily_dimension_installs
     WHERE day = ?
     GROUP BY dimension, value
     ORDER BY count DESC
     LIMIT 200`
  ).bind(today).all();

  const monthDimensions = await db.prepare(
    `SELECT dimension, value, COUNT(DISTINCT install_id) AS count
     FROM daily_dimension_installs
     WHERE day >= ?
     GROUP BY dimension, value
     ORDER BY count DESC
     LIMIT 200`
  ).bind(monthStart).all();

  const installs = await db.prepare("SELECT COUNT(*) AS count FROM installs").first();
  const active = await db.prepare(
    "SELECT COUNT(*) AS count FROM active_sessions WHERE last_seen_at >= ?"
  ).bind(activeSince).first();

  return {
    generated_at: new Date(now * 1000).toISOString(),
    active_window_minutes: ACTIVE_WINDOW_SECONDS / 60,
    anonymous_installs: installs?.count || 0,
    active_now: active?.count || 0,
    unique_events: rowsToObject(totals.results, "event"),
    unique_events_today: rowsToObject(todayTotals.results, "event"),
    unique_events_month: rowsToObject(monthTotals.results, "event"),
    unique_dimensions: groupDimensions(dimensions.results),
    unique_dimensions_today: groupDimensions(todayDimensions.results),
    unique_dimensions_month: groupDimensions(monthDimensions.results),
  };
}

function normalizedDimensions(input) {
  return {
    app_version: sanitizeText(input.app_version, 32),
    wow_version: sanitizeText(input.wow_version, 32),
    renderer: sanitizeText(input.renderer || "d9vk", 32),
    x87_translation: sanitizeEnum(input.x87_translation, ["disabled", "rosettax87", "x87sidecar"]),
    macos_version: sanitizeText(input.macos_version, 32),
    realmlist: sanitizeRealm(input.realmlist),
  };
}

function sanitizeId(value) {
  if (typeof value !== "string") return null;
  return /^[a-zA-Z0-9_-]{16,64}$/.test(value) ? value : null;
}

function sanitizeEnum(value, allowed) {
  return allowed.includes(value) ? value : null;
}

function sanitizeText(value, maxLength) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().toLowerCase();
  if (!cleaned || cleaned.length > maxLength) return null;
  return cleaned.replace(/[^a-z0-9._ -]/g, "");
}

function sanitizeRealm(value) {
  if (typeof value !== "string") return null;
  const cleaned = value.trim().toLowerCase().replace(/^set\s+realmlist\s+/i, "");
  if (!cleaned || cleaned.length > 128) return null;
  return cleaned.replace(/[^a-z0-9.:-]/g, "");
}

function rowsToObject(rows, key) {
  const out = {};
  for (const row of rows || []) {
    out[row[key]] = row.count;
  }
  return out;
}

function groupDimensions(rows) {
  const grouped = {};
  for (const row of rows || []) {
    grouped[row.dimension] ||= [];
    grouped[row.dimension].push({ value: row.value, count: row.count });
  }
  return grouped;
}

function json(data, headers = {}, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
      ...headers,
    },
  });
}
