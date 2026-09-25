const CONFIG = {
  telemetry_enabled: true,
  heartbeat_enabled: true,
  heartbeat_interval_minutes: 15,
  launch_sample_rate: 1.0,
  heartbeat_sample_rate: 1.0,
  config_ttl_hours: 1,
  min_supported_telemetry_schema: 1,
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

const MAX_BODY_BYTES = 4096;
const ACTIVE_WINDOW_SECONDS = 30 * 60;
const HEARTBEAT_DEDUPE_SECONDS = 5 * 60;

export default {
  async fetch(request, env, ctx) {
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
      return json(await getStats(env.DB, request, ctx));
    }

    if (request.method === "GET" && url.pathname === "/live.json") {
      return json(await cachedData(request, ctx, `live-v1-${Math.floor(Date.now() / 60000)}`, 60,
        () => getLive(env.DB)), { "Cache-Control": "public, max-age=30" });
    }

    if (request.method === "GET" && url.pathname === "/history.json") {
      return json(await cachedData(request, ctx, `history-${new Date().toISOString().slice(0, 10)}`, 21600, () => getHistory(env.DB)), {
        "Cache-Control": "public, max-age=300",
      });
    }

    if (request.method === "GET" && url.pathname === "/report.json") {
      const period = url.searchParams.get("period") || "30";
      const version = url.searchParams.get("version") || "";
      const day = url.searchParams.get("day") || "";
      const today = new Date().toISOString().slice(0, 10);
      if (!["today", "7", "30", "90", "month", "all", "day"].includes(period) ||
          (period === "day" && (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day > today)) ||
          (period !== "day" && day) ||
          (version && !/^[a-z0-9][a-z0-9._ -]{0,31}$/.test(version))) {
        return json({ error: "invalid_filter" }, {}, 400);
      }
      if (version) {
        const history = await cachedData(request, ctx, `history-${today}`, 21600, () => getHistory(env.DB));
        if (!history.days.some(item => item.players_by_wow_version?.some(row => row.value === version))) {
          return json({ error: "unknown_version" }, {}, 400);
        }
      }
      const cacheKey = `report-v1-${today}-${period}-${day}-${version}`;
      return json(await cachedData(request, ctx, cacheKey, period === "today" ? 300 : 21600,
        () => getReport(env.DB, period, day, version, today)), {
        "Cache-Control": "public, max-age=300",
      });
    }

    if (request.method === "POST" && url.pathname === "/event") {
      return handleEvent(request, env.DB);
    }

    return json({ error: "not_found" }, {}, 404);
  },
};

async function cachedData(request, ctx, name, ttlSeconds, load) {
  const origin = new URL(request.url).origin;
  const key = new Request(`${origin}/__telemetry_cache/${name}`);
  const cache = caches.default;
  const cached = await cache.match(key);
  if (cached) return cached.json();

  const data = await load();
  ctx.waitUntil(cache.put(key, new Response(JSON.stringify(data), {
    headers: { "Cache-Control": `public, max-age=${ttlSeconds}` },
  })));
  return data;
}

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

  const event = sanitizeEnum(input.event, ["launch", "wow_start", "heartbeat", "session_end"]);
  const installId = sanitizeId(input.install_id);
  const sessionId = sanitizeId(input.session_id || input.install_id);

  if (!CONFIG.telemetry_enabled) {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (!event || !installId) {
    return json({ error: "invalid_event" }, {}, 400);
  }

  if ((event === "heartbeat" || event === "session_end") && !CONFIG.heartbeat_enabled) {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const now = Math.floor(Date.now() / 1000);
  if (event === "heartbeat") {
    await db.prepare(
      "UPDATE active_sessions SET last_seen_at = ? WHERE session_id = ? AND install_id = ? AND last_seen_at <= ?"
    ).bind(now, sessionId, installId, now - HEARTBEAT_DEDUPE_SECONDS).run();
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (event === "session_end") {
    await db.prepare("DELETE FROM active_sessions WHERE session_id = ? AND install_id = ?")
      .bind(sessionId, installId).run();
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const day = new Date(now * 1000).toISOString().slice(0, 10);
  const dimensions = normalizedDimensions(input);

  if (event === "wow_start" && Math.random() < 0.02) {
    await db.prepare("DELETE FROM active_sessions WHERE last_seen_at < ?")
      .bind(now - 24 * 60 * 60).run();
  }

  await db.prepare(
    `INSERT INTO installs (install_id, first_seen_at, last_seen_at)
     VALUES (?, ?, ?)
     ON CONFLICT(install_id) DO UPDATE SET last_seen_at = excluded.last_seen_at`
  ).bind(installId, now, now).run();

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

  if (event === "wow_start") {
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

async function getStats(db, request, ctx) {
  const now = Math.floor(Date.now() / 1000);
  const activeSince = now - ACTIVE_WINDOW_SECONDS;
  const today = new Date(now * 1000).toISOString().slice(0, 10);
  const monthStart = today.slice(0, 7) + "-01";

  const historical = await cachedData(request, ctx, `all-time-${today}`, 86400, async () => {
    const totals = await db.prepare(
      `SELECT event, COUNT(*) AS count
       FROM daily_event_installs
       GROUP BY event`
    ).all();

    const dimensions = await db.prepare(
      `SELECT dimension, value, COUNT(*) AS count
       FROM daily_dimension_installs
       GROUP BY dimension, value
       ORDER BY count DESC
       LIMIT 200`
    ).all();

    return {
      events: rowsToObject(totals.results, "event"),
      dimensions: groupDimensions(dimensions.results),
    };
  });

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
    unique_events: historical.events,
    unique_events_today: rowsToObject(todayTotals.results, "event"),
    unique_events_month: rowsToObject(monthTotals.results, "event"),
    unique_dimensions: historical.dimensions,
    unique_dimensions_today: groupDimensions(todayDimensions.results),
    unique_dimensions_month: groupDimensions(monthDimensions.results),
  };
}

async function getLive(db) {
  const now = Math.floor(Date.now() / 1000);
  const active = await db.prepare(
    "SELECT install_id, wow_version FROM active_sessions WHERE last_seen_at >= ?"
  ).bind(now - ACTIVE_WINDOW_SECONDS).all();
  const installs = new Set();
  const versions = new Map();
  for (const row of active.results || []) {
    installs.add(row.install_id);
    if (row.wow_version) {
      if (!versions.has(row.wow_version)) versions.set(row.wow_version, new Set());
      versions.get(row.wow_version).add(row.install_id);
    }
  }
  return {
    generated_at: new Date(now * 1000).toISOString(),
    window_minutes: ACTIVE_WINDOW_SECONDS / 60,
    count: installs.size,
    by_version: Object.fromEntries([...versions].map(([version, ids]) => [version, ids.size])),
  };
}

function normalizedDimensions(input) {
  return {
    app_version: sanitizeText(input.app_version, 32),
    wow_version: sanitizeText(input.wow_version, 32),
    renderer: sanitizeText(input.renderer || "d9vk", 32),
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

async function getHistory(db) {
  const events = await db.prepare(
    `SELECT day, event, COUNT(*) AS count
     FROM daily_event_installs
     WHERE event IN ('launch', 'wow_start')
     GROUP BY day, event
     ORDER BY day`
  ).all();

  const dimensions = await db.prepare(
    `SELECT day, dimension, value, COUNT(*) AS count
     FROM daily_dimension_installs
     WHERE dimension IN ('wow_version', 'app_version', 'macos_version', 'renderer')
     GROUP BY day, dimension, value
     ORDER BY day`
  ).all();

  const playersByVersion = await db.prepare(
    `SELECT e.day, d.value, COUNT(*) AS count
     FROM daily_event_installs e
     JOIN daily_dimension_installs d
       ON d.day = e.day AND d.install_id = e.install_id
     WHERE e.event = 'wow_start' AND d.dimension = 'wow_version'
     GROUP BY e.day, d.value
     ORDER BY e.day`
  ).all();

  const days = new Map();
  function getDay(date) {
    if (!days.has(date)) {
      days.set(date, { date, unique_events: {}, unique_dimensions: {}, players_by_wow_version: [] });
    }
    return days.get(date);
  }

  for (const row of events.results || []) {
    getDay(row.day).unique_events[row.event] = row.count;
  }
  for (const row of dimensions.results || []) {
    const groups = getDay(row.day).unique_dimensions;
    (groups[row.dimension] ||= []).push({ value: row.value, count: row.count });
  }
  for (const row of playersByVersion.results || []) {
    getDay(row.day).players_by_wow_version.push({ value: row.value, count: row.count });
  }

  return { days: [...days.values()].sort((a, b) => a.date.localeCompare(b.date)) };
}

async function getReport(db, period, day, version, today) {
  const start = new Date(`${today}T00:00:00Z`);
  if (["7", "30", "90"].includes(period)) start.setUTCDate(start.getUTCDate() - Number(period) + 1);
  const from = period === "day" ? day : period === "all" ? "0000-01-01" :
    period === "month" ? `${today.slice(0, 7)}-01` : start.toISOString().slice(0, 10);
  const to = period === "day" ? day : today;
  const versionFilter = version ?
    `AND EXISTS (SELECT 1 FROM daily_dimension_installs v
      WHERE v.day = e.day AND v.dimension = 'wow_version'
        AND v.value = ? AND v.install_id = e.install_id)` : "";
  const eventSql = `SELECT e.event, COUNT(DISTINCT e.install_id) AS count
    FROM daily_event_installs e
    WHERE e.day BETWEEN ? AND ? AND e.event IN ('launch', 'wow_start') ${versionFilter}
    GROUP BY e.event`;
  const eventArgs = version ? [from, to, version] : [from, to];
  const eventRows = await db.prepare(eventSql).bind(...eventArgs).all();

  const dimensionSql = `SELECT d.dimension, d.value, COUNT(DISTINCT d.install_id) AS count
    FROM daily_dimension_installs d
    WHERE d.day BETWEEN ? AND ?
      AND d.dimension IN ('wow_version', 'app_version', 'macos_version', 'renderer', 'realmlist')
      AND EXISTS (SELECT 1 FROM daily_event_installs e
        WHERE e.day = d.day AND e.event = 'wow_start' AND e.install_id = d.install_id
        ${versionFilter})
    GROUP BY d.dimension, d.value
    ORDER BY count DESC LIMIT 500`;
  const dimensionArgs = version ? [from, to, version] : [from, to];
  const dimensionRows = await db.prepare(dimensionSql).bind(...dimensionArgs).all();

  return {
    generated_at: new Date().toISOString(),
    from, to, version,
    unique_events: rowsToObject(eventRows.results, "event"),
    unique_dimensions: groupDimensions(dimensionRows.results),
  };
}
