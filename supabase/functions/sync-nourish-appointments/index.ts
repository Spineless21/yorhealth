const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const clientId = Deno.env.get("NOURISH_CLIENT_ID");
const clientSecret = Deno.env.get("NOURISH_CLIENT_SECRET");
const orgName = Deno.env.get("NOURISH_ORGANISATION_NAME");
const onBehalfOf = Deno.env.get("NOURISH_ON_BEHALF_OF");
const syncSecret = Deno.env.get("SYNC_SECRET");
const functionVersion = "sync-nourish-appointments-rest-v2-2026-05-28";

const apiBase = "https://api.nourishcare.com";
const pageSize = 200;
const maxWindowDays = 14;

type Json = Record<string, unknown>;

const debugSteps: Json[] = [];

function jsonResponse(status: number, body: Json) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;

  try {
    return JSON.stringify(error);
  } catch {
    return "Unknown error";
  }
}

function asString(value: unknown) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function asNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function asBoolean(value: unknown) {
  return typeof value === "boolean" ? value : false;
}

function asDate(value: unknown) {
  const text = asString(value);
  return text ? text : null;
}

function getNestedString(obj: unknown, path: string[]) {
  let current = obj as Record<string, unknown> | null;
  for (const key of path) {
    if (!current || typeof current !== "object") return null;
    current = current[key] as Record<string, unknown> | null;
  }
  return asString(current);
}

function addDays(date: Date, days: number) {
  const next = new Date(date);
  next.setUTCDate(next.getUTCDate() + days);
  return next;
}

function iso(date: Date) {
  return date.toISOString();
}

function startOfUtcDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

async function restWrite(
  operation: string,
  table: string,
  method: "POST" | "PATCH",
  body: unknown,
  query = "",
  prefer = "return=minimal",
) {
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }

  const url = `${supabaseUrl}/rest/v1/${table}${query}`;

  debugSteps.push({
    operation,
    table,
    method,
    query,
    body_is_array: Array.isArray(body),
    body_count: Array.isArray(body) ? body.length : 1,
  });

  const response = await fetch(url, {
    method,
    headers: {
      apikey: serviceRoleKey!,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      Prefer: prefer,
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();

  if (!response.ok) {
    throw new Error(`${operation} failed: ${response.status} ${text}`);
  }

  return text;
}

function appointmentDates(appointment: Json) {
  const dates = appointment.dates as Json | undefined;
  return {
    start:
      asDate(dates?.start) ??
      asDate(appointment.start) ??
      asDate(appointment.startAt),
    end:
      asDate(dates?.end) ??
      asDate(appointment.end) ??
      asDate(appointment.endAt),
    timezone:
      asString(dates?.timezone) ??
      asString(appointment.timezone),
  };
}

function appointmentCarerSlots(appointment: Json) {
  const carers = Array.isArray(appointment.carers) ? appointment.carers : [];
  const carerSlots = Array.isArray(appointment.carerSlots) ? appointment.carerSlots : [];
  return [...carers, ...carerSlots] as Json[];
}

function carerIdentifier(slot: Json) {
  return (
    asString(slot.carer) ??
    asString(slot.carerIdentifier) ??
    asString(slot.carerUuid) ??
    asString(slot.identifier) ??
    getNestedString(slot.carer as Json | undefined, ["identifier"]) ??
    getNestedString(slot.user as Json | undefined, ["identifier"])
  );
}

function slotIdentifier(slot: Json) {
  return (
    asString(slot.slotIdentifier) ??
    asString(slot.identifier) ??
    asString(slot.uuid)
  );
}

function slotKey(appointmentIdentifier: string, slot: Json, index: number) {
  const slotId = slotIdentifier(slot) ?? `slot-${asNumber(slot.slot) ?? index}`;
  const carerId = carerIdentifier(slot) ?? "unassigned";
  return `${appointmentIdentifier}:${slotId}:${carerId}`;
}

async function getToken() {
  if (!clientId || !clientSecret) {
    throw new Error("Missing NOURISH_CLIENT_ID or NOURISH_CLIENT_SECRET");
  }

  const body = {
    grant_type: "client_credentials",
    client_id: clientId,
    client_secret: clientSecret,
  };

  const response = await fetch(`${apiBase}/oauth2/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Token request failed: ${response.status} ${await response.text()}`);
  }

  const json = await response.json();
  const token = asString(json.access_token);
  if (!token) throw new Error("Token response did not include access_token");
  return token;
}

async function listAppointments(token: string, start: string, end: string, offset: number) {
  if (!orgName) throw new Error("Missing NOURISH_ORGANISATION_NAME");

  const filters = {
    start,
    end,
    excludeDeleted: false,
    excludeCancelled: false,
    persistedOnly: false,
  };

  const url = new URL(`${apiBase}/appointments`);
  url.searchParams.set("limit", String(pageSize));
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("filters", JSON.stringify(filters));

  const headers: HeadersInit = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
    "CP-Org-Name": orgName,
  };

  if (onBehalfOf) {
    headers["CP-On-Behalf-Of"] = onBehalfOf;
  }

  const response = await fetch(url, { headers });

  if (!response.ok) {
    throw new Error(`Appointments request failed: ${response.status} ${await response.text()}`);
  }

  const json = await response.json();
  if (Array.isArray(json)) return json as Json[];
  if (Array.isArray(json.appointments)) return json.appointments as Json[];
  if (Array.isArray(json.data)) return json.data as Json[];
  if (Array.isArray(json.results)) return json.results as Json[];
  return [];
}

async function upsertAppointment(appointment: Json, rangeStart: string, rangeEnd: string) {
  const identifier = asString(appointment.identifier);
  if (!identifier) return { appointments: 0, carers: 0 };

  debugSteps.push({ operation: "upsertAppointment start", appointment_identifier: identifier });

  const dates = appointmentDates(appointment);
  const cancelled = asBoolean(appointment.cancelled);
  const deleted = asBoolean(appointment.deleted) ||
    asBoolean(appointment.deletedFromCarerRoster) ||
    asBoolean(appointment.deletedFromClientRoster);

  await restWrite(
    "appointments_raw upsert",
    "appointments_raw",
    "POST",
    {
      appointment_identifier: identifier,
      payload: appointment,
      range_start: rangeStart,
      range_end: rangeEnd,
      last_updated: asDate(appointment.lastUpdated),
      synced_at: new Date().toISOString(),
      is_active: !deleted,
    },
    "?on_conflict=appointment_identifier",
    "resolution=merge-duplicates,return=minimal",
  );

  await restWrite(
    "appointments upsert",
    "appointments",
    "POST",
    {
      appointment_identifier: identifier,
      internal_identifier: asNumber(appointment.internalIdentifier),
      version: asNumber(appointment.version),
      client_identifier: asString(appointment.client),
      appointment_preset: asNumber(appointment.appointmentPreset),
      start_at: dates.start,
      end_at: dates.end,
      timezone: dates.timezone,
      status: asString(appointment.status),
      cancelled,
      deleted,
      last_updated: asDate(appointment.lastUpdated),
      payload: appointment,
      synced_at: new Date().toISOString(),
      is_active: !deleted,
    },
    "?on_conflict=appointment_identifier",
    "resolution=merge-duplicates,return=minimal",
  );

  await restWrite(
    "appointment_carers deactivate",
    "appointment_carers",
    "PATCH",
    { is_active: false, synced_at: new Date().toISOString() },
    `?appointment_identifier=eq.${encodeURIComponent(identifier)}`,
  );

  const slots = appointmentCarerSlots(appointment);
  if (slots.length === 0) return { appointments: 1, carers: 0 };

  const rows = slots.map((slot, index) => ({
    appointment_carer_key: slotKey(identifier, slot, index),
    appointment_identifier: identifier,
    slot_identifier: slotIdentifier(slot),
    carer_identifier: carerIdentifier(slot),
    slot: asNumber(slot.slot),
    run_identifier: asString(slot.run) ?? asString(slot.runIdentifier),
    required: typeof slot.required === "boolean" ? slot.required : null,
    start_at: asDate(slot.start) ?? dates.start,
    end_at: asDate(slot.end) ?? dates.end,
    status: asString(slot.status),
    cancelled,
    deleted,
    payload: slot,
    synced_at: new Date().toISOString(),
    is_active: !deleted,
  }));

  const uniqueRows = Array.from(
    new Map(rows.map((row) => [row.appointment_carer_key, row])).values(),
  );

  debugSteps.push({
    operation: "appointment_carers prepared",
    appointment_identifier: identifier,
    raw_slots: rows.length,
    unique_slots: uniqueRows.length,
  });

  await restWrite(
    "appointment_carers upsert",
    "appointment_carers",
    "POST",
    uniqueRows,
    "?on_conflict=appointment_carer_key",
    "resolution=merge-duplicates,return=minimal",
  );

  return { appointments: 1, carers: uniqueRows.length };
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);

    if (url.searchParams.get("health") === "1") {
      return jsonResponse(200, {
        ok: true,
        function: "sync-nourish-appointments",
        version: functionVersion,
        uses_supabase_js: false,
        default_days: 7,
        has_supabase_url: Boolean(supabaseUrl),
        has_service_role_key: Boolean(serviceRoleKey),
        has_nourish_client_id: Boolean(clientId),
        has_nourish_client_secret: Boolean(clientSecret),
        has_nourish_organisation_name: Boolean(orgName),
        has_sync_secret: Boolean(syncSecret),
      });
    }

    if (syncSecret) {
      const provided = req.headers.get("x-sync-secret");
      if (provided !== syncSecret) {
        return jsonResponse(401, { error: "Unauthorized" });
      }
    }

    const days = Number.parseInt(url.searchParams.get("days") ?? "7", 10);
    const startParam = url.searchParams.get("start");
    const endParam = url.searchParams.get("end");

    const startDate = startParam ? new Date(startParam) : startOfUtcDay(new Date());
    const finalEndDate = endParam ? new Date(endParam) : addDays(startDate, days);

    if (Number.isNaN(startDate.getTime()) || Number.isNaN(finalEndDate.getTime())) {
      return jsonResponse(400, { error: "Invalid start/end date" });
    }

    const token = await getToken();
    let totalAppointments = 0;
    let totalCarerSlots = 0;
    let windows = 0;

    for (let windowStart = startDate; windowStart < finalEndDate; windowStart = addDays(windowStart, maxWindowDays)) {
      const windowEnd = addDays(windowStart, maxWindowDays) < finalEndDate
        ? addDays(windowStart, maxWindowDays)
        : finalEndDate;

      windows += 1;
      let offset = 0;

      while (true) {
        const appointments = await listAppointments(token, iso(windowStart), iso(windowEnd), offset);
        if (appointments.length === 0) break;

        for (const appointment of appointments) {
          const result = await upsertAppointment(appointment, iso(windowStart), iso(windowEnd));
          totalAppointments += result.appointments;
          totalCarerSlots += result.carers;
        }

        if (appointments.length < pageSize) break;
        offset += pageSize;
      }
    }

    return jsonResponse(200, {
      ok: true,
      windows,
      appointments_upserted: totalAppointments,
      carer_slots_upserted: totalCarerSlots,
      start: iso(startDate),
      end: iso(finalEndDate),
      version: functionVersion,
    });
  } catch (error) {
    console.error(error);
    return jsonResponse(500, {
      ok: false,
      error: errorMessage(error),
      debug_steps: debugSteps.slice(-12),
    });
  }
});
