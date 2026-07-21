const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const clientId = Deno.env.get("NOURISH_CLIENT_ID");
const clientSecret = Deno.env.get("NOURISH_CLIENT_SECRET");
const orgName = Deno.env.get("NOURISH_ORGANISATION_NAME");
const onBehalfOf = Deno.env.get("NOURISH_ON_BEHALF_OF");
const syncSecret = Deno.env.get("SYNC_SECRET");
const functionVersion = "sync-nourish-timesheets-rest-v1-2026-06-08";

const apiBase = "https://api.nourishcare.com";
const pageSize = 200;
const defaultDaysBack = 90;
const defaultDaysForward = 14;

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
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asInteger(value: unknown) {
  const parsed = asNumber(value);
  return parsed === null ? null : Math.trunc(parsed);
}

function asBoolean(value: unknown) {
  return typeof value === "boolean" ? value : null;
}

function asDate(value: unknown) {
  const text = asString(value);
  return text ? text : null;
}

function asDateOnly(value: unknown) {
  const text = asString(value);
  if (!text) return null;
  return text.slice(0, 10);
}

function asJsonArray(value: unknown) {
  return Array.isArray(value) ? value : [];
}

function addDays(date: Date, days: number) {
  const next = new Date(date);
  next.setUTCDate(next.getUTCDate() + days);
  return next;
}

function startOfUtcDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function iso(date: Date) {
  return date.toISOString();
}

function nourishDateTime(date: Date) {
  return date.toISOString().replace(/\.\d{3}Z$/, "+00:00");
}

function isoDate(date: Date) {
  return iso(date).slice(0, 10);
}

function tableUrl(table: string, query = "") {
  if (!supabaseUrl) throw new Error("Missing SUPABASE_URL");
  return `${supabaseUrl}/rest/v1/${table}${query}`;
}

async function restRequest(
  operation: string,
  table: string,
  method: "POST" | "PATCH",
  body: unknown,
  query = "",
  prefer = "return=minimal",
) {
  if (!serviceRoleKey) throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY");

  debugSteps.push({
    operation,
    table,
    method,
    query,
    body_is_array: Array.isArray(body),
    body_count: Array.isArray(body) ? body.length : 1,
  });

  const response = await fetch(tableUrl(table, query), {
    method,
    headers: {
      apikey: serviceRoleKey,
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

async function insertSyncRun(startDate: string, endDate: string, metadata: Json) {
  const text = await restRequest(
    "timesheet_sync_runs insert",
    "timesheet_sync_runs",
    "POST",
    {
      status: "running",
      requested_start_date: startDate,
      requested_end_date: endDate,
      metadata,
    },
    "",
    "return=representation",
  );

  const rows = JSON.parse(text);
  const id = Array.isArray(rows) ? asInteger(rows[0]?.id) : null;
  if (!id) throw new Error("Could not create timesheet sync run");
  return id;
}

async function updateSyncRun(syncRunId: number, patch: Json) {
  await restRequest(
    "timesheet_sync_runs update",
    "timesheet_sync_runs",
    "PATCH",
    patch,
    `?id=eq.${syncRunId}`,
  );
}

async function getToken() {
  if (!clientId || !clientSecret) {
    throw new Error("Missing NOURISH_CLIENT_ID or NOURISH_CLIENT_SECRET");
  }

  const response = await fetch(`${apiBase}/oauth2/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });

  if (!response.ok) {
    throw new Error(`Token request failed: ${response.status} ${await response.text()}`);
  }

  const json = await response.json();
  const token = asString(json.access_token);
  if (!token) throw new Error("Token response did not include access_token");
  return token;
}

function nourishHeaders(token: string) {
  if (!orgName) throw new Error("Missing NOURISH_ORGANISATION_NAME");

  const headers: HeadersInit = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
    "CP-Org-Name": orgName,
  };

  if (onBehalfOf) {
    headers["CP-On-Behalf-Of"] = onBehalfOf;
  }

  return headers;
}

function extractRows(payload: unknown): Json[] {
  if (Array.isArray(payload)) return payload as Json[];
  const obj = payload as Json | null;
  if (!obj || typeof obj !== "object") return [];
  if (Array.isArray(obj.data)) return obj.data as Json[];
  if (Array.isArray(obj.results)) return obj.results as Json[];
  if (Array.isArray(obj.items)) return obj.items as Json[];
  if (Array.isArray(obj.timesheets)) return obj.timesheets as Json[];
  return [];
}

async function listTimesheets(
  token: string,
  start: string,
  end: string,
  offset: number,
  modifiedAfter: string | null,
) {
  const filters: Json = {
    start,
    end,
  };

  if (modifiedAfter) {
    filters.modifiedAfter = modifiedAfter;
  }

  const url = new URL(`${apiBase}/finance/timesheets`);
  url.searchParams.set("limit", String(pageSize));
  url.searchParams.set("offset", String(offset));
  url.searchParams.set("filters", JSON.stringify(filters));

  const response = await fetch(url, {
    headers: nourishHeaders(token),
  });

  if (!response.ok) {
    throw new Error(`Timesheets request failed: ${response.status} ${await response.text()}`);
  }

  return extractRows(await response.json());
}

async function getTimesheetDetails(token: string, timesheetIdentifier: string) {
  const response = await fetch(`${apiBase}/finance/timesheets/${encodeURIComponent(timesheetIdentifier)}`, {
    headers: nourishHeaders(token),
  });

  if (!response.ok) {
    throw new Error(`Timesheet details request failed for ${timesheetIdentifier}: ${response.status} ${await response.text()}`);
  }

  return await response.json() as Json;
}

function timesheetIdentifier(timesheet: Json) {
  return asString(timesheet.identifier) ?? asString(timesheet.uuid) ?? asString(timesheet.id);
}

function lineItemKey(timesheetId: string, item: Json, index: number) {
  return `${timesheetId}:line:${index}`;
}

function extraItemKey(timesheetId: string, item: Json, index: number) {
  return `${timesheetId}:extra:${index}`;
}

async function upsertTimesheet(timesheet: Json, syncRunId: number) {
  const identifier = timesheetIdentifier(timesheet);
  if (!identifier) return { timesheets: 0, lineItems: 0, extraItems: 0 };

  const now = new Date().toISOString();
  const lineItems = asJsonArray(timesheet.lineItems) as Json[];
  const extraItems = asJsonArray(timesheet.extraItems) as Json[];

  await restRequest(
    "timesheets_raw upsert",
    "timesheets_raw",
    "POST",
    {
      timesheet_identifier: identifier,
      payload: timesheet,
      period_start: asDateOnly(timesheet.start),
      period_end: asDateOnly(timesheet.end),
      issued_date: asDateOnly(timesheet.issued),
      paid_status: asString(timesheet.paidStatus),
      carer_identifier: asString(timesheet.carer),
      synced_at: now,
      sync_run_id: syncRunId,
      is_active: true,
    },
    "?on_conflict=timesheet_identifier",
    "resolution=merge-duplicates,return=minimal",
  );

  await restRequest(
    "timesheets upsert",
    "timesheets",
    "POST",
    {
      timesheet_identifier: identifier,
      carer_identifier: asString(timesheet.carer),
      payment_group: asString(timesheet.paymentGroup),
      period_start: asDateOnly(timesheet.start),
      period_end: asDateOnly(timesheet.end),
      issued_date: asDateOnly(timesheet.issued),
      paid_status: asString(timesheet.paidStatus),
      regions: Array.isArray(timesheet.regions) ? timesheet.regions : [],
      all_regions: asBoolean(timesheet.allRegions),
      formatted_timesheet_number: asString(timesheet.formattedTimesheetNumber),
      address: asString(timesheet.address),
      carer_max_hours: asInteger(timesheet.carerMaxHours),
      carer_payroll_number: asString(timesheet.carerPayrollNumber),
      total_cost: asNumber(timesheet.total),
      totals: typeof timesheet.totals === "object" && timesheet.totals !== null ? timesheet.totals : {},
      metadata: typeof timesheet.metadata === "object" && timesheet.metadata !== null ? timesheet.metadata : {},
      payload: timesheet,
      synced_at: now,
      sync_run_id: syncRunId,
      is_active: true,
    },
    "?on_conflict=timesheet_identifier",
    "resolution=merge-duplicates,return=minimal",
  );

  await restRequest(
    "timesheet_line_items deactivate",
    "timesheet_line_items",
    "PATCH",
    { is_active: false, synced_at: now, sync_run_id: syncRunId },
    `?timesheet_identifier=eq.${encodeURIComponent(identifier)}`,
  );

  await restRequest(
    "timesheet_extra_items deactivate",
    "timesheet_extra_items",
    "PATCH",
    { is_active: false, synced_at: now, sync_run_id: syncRunId },
    `?timesheet_identifier=eq.${encodeURIComponent(identifier)}`,
  );

  if (lineItems.length > 0) {
    const rows = lineItems.map((item, index) => ({
      line_item_key: lineItemKey(identifier, item, index),
      timesheet_identifier: identifier,
      line_item_index: index,
      line_type: asString(item.type),
      entity_identifier: asString(item.entity),
      client_identifier: asString(item.client),
      rate_identifier: asString(item.rate),
      version: asInteger(item.version),
      cancelled: asBoolean(item.cancelled) ?? false,
      start_at: asDate(item.start),
      end_at: asDate(item.end),
      rate_of_pay: asNumber(item.rateOfPay),
      rate_description: asString(item.rateDescription),
      rate_name: asString(item.rateName),
      cost: asNumber(item.cost),
      client_mileage_cost: asNumber(item.clientMileageCost),
      client_mileage_distance: asNumber(item.clientMileageDistance),
      travel_mileage_cost: asNumber(item.travelMileageCost),
      travel_mileage_distance: asNumber(item.travelMileageDistance),
      travel_time_cost: asNumber(item.travelTimeCost),
      travel_time_minutes: asInteger(item.travelTime),
      waiting_time_cost: asNumber(item.waitingTimeCost),
      waiting_time_minutes: asInteger(item.waitingTime),
      cancellation_fee: asInteger(item.cancellationFee),
      break_time_minutes: asInteger(item.breakTime),
      duration_minutes: asInteger(item.duration),
      booking_reference: asString(item.bookingReference),
      payload: item,
      synced_at: now,
      sync_run_id: syncRunId,
      is_active: true,
    }));

    const uniqueRows = Array.from(
      new Map(rows.map((row) => [row.line_item_key, row])).values(),
    );

    await restRequest(
      "timesheet_line_items upsert",
      "timesheet_line_items",
      "POST",
      uniqueRows,
      "?on_conflict=line_item_key",
      "resolution=merge-duplicates,return=minimal",
    );
  }

  if (extraItems.length > 0) {
    const rows = extraItems.map((item, index) => ({
      extra_item_key: extraItemKey(identifier, item, index),
      timesheet_identifier: identifier,
      extra_item_index: index,
      description: asString(item.description),
      cost: asNumber(item.cost),
      payload: item,
      synced_at: now,
      sync_run_id: syncRunId,
      is_active: true,
    }));

    const uniqueRows = Array.from(
      new Map(rows.map((row) => [row.extra_item_key, row])).values(),
    );

    await restRequest(
      "timesheet_extra_items upsert",
      "timesheet_extra_items",
      "POST",
      uniqueRows,
      "?on_conflict=extra_item_key",
      "resolution=merge-duplicates,return=minimal",
    );
  }

  return {
    timesheets: 1,
    lineItems: lineItems.length,
    extraItems: extraItems.length,
  };
}

Deno.serve(async (req) => {
  let syncRunId: number | null = null;

  try {
    const url = new URL(req.url);

    if (url.searchParams.get("health") === "1") {
      return jsonResponse(200, {
        ok: true,
        function: "sync-nourish-timesheets",
        version: functionVersion,
        uses_supabase_js: false,
        default_days_back: defaultDaysBack,
        default_days_forward: defaultDaysForward,
        has_supabase_url: Boolean(supabaseUrl),
        has_service_role_key: Boolean(serviceRoleKey),
        has_nourish_client_id: Boolean(clientId),
        has_nourish_client_secret: Boolean(clientSecret),
        has_nourish_organisation_name: Boolean(orgName),
        has_sync_secret: Boolean(syncSecret),
      });
    }

    if (syncSecret) {
      const provided = req.headers.get("x-sync-secret") ?? url.searchParams.get("sync_secret");
      if (provided !== syncSecret) {
        return jsonResponse(401, { ok: false, error: "Unauthorized" });
      }
    }

    const now = startOfUtcDay(new Date());
    const daysBack = Number.parseInt(url.searchParams.get("days_back") ?? String(defaultDaysBack), 10);
    const daysForward = Number.parseInt(url.searchParams.get("days_forward") ?? String(defaultDaysForward), 10);
    const maxPages = Number.parseInt(url.searchParams.get("max_pages") ?? "50", 10);
    const fetchDetails = url.searchParams.get("details") === "1";
    const modifiedAfter = url.searchParams.get("modified_after");
    const startParam = url.searchParams.get("start");
    const endParam = url.searchParams.get("end");

    const startDate = startParam ? new Date(startParam) : addDays(now, -daysBack);
    const endDate = endParam ? new Date(endParam) : addDays(now, daysForward);

    if (
      Number.isNaN(startDate.getTime()) ||
      Number.isNaN(endDate.getTime()) ||
      Number.isNaN(daysBack) ||
      Number.isNaN(daysForward) ||
      Number.isNaN(maxPages)
    ) {
      return jsonResponse(400, { ok: false, error: "Invalid date/window parameter" });
    }

    syncRunId = await insertSyncRun(isoDate(startDate), isoDate(endDate), {
      version: functionVersion,
      fetch_details: fetchDetails,
      modified_after: modifiedAfter,
      max_pages: maxPages,
    });

    const token = await getToken();
    let offset = 0;
    let pages = 0;
    let seen = 0;
    let timesheetsUpserted = 0;
    let lineItemsUpserted = 0;
    let extraItemsUpserted = 0;

    while (pages < maxPages) {
      const timesheets = await listTimesheets(
        token,
        nourishDateTime(startDate),
        nourishDateTime(endDate),
        offset,
        modifiedAfter,
      );
      if (timesheets.length === 0) break;

      pages += 1;
      seen += timesheets.length;

      for (const listedTimesheet of timesheets) {
        const identifier = timesheetIdentifier(listedTimesheet);
        const needsDetails = fetchDetails || !Array.isArray(listedTimesheet.lineItems);
        const timesheet = needsDetails && identifier
          ? await getTimesheetDetails(token, identifier)
          : listedTimesheet;

        const result = await upsertTimesheet(timesheet, syncRunId);
        timesheetsUpserted += result.timesheets;
        lineItemsUpserted += result.lineItems;
        extraItemsUpserted += result.extraItems;
      }

      if (timesheets.length < pageSize) break;
      offset += pageSize;
    }

    await updateSyncRun(syncRunId, {
      finished_at: new Date().toISOString(),
      status: "success",
      timesheets_seen: seen,
      timesheets_upserted: timesheetsUpserted,
      line_items_upserted: lineItemsUpserted,
      extra_items_upserted: extraItemsUpserted,
      metadata: {
        version: functionVersion,
        pages,
        start: iso(startDate),
        end: iso(endDate),
        modified_after: modifiedAfter,
        fetch_details: fetchDetails,
      },
    });

    return jsonResponse(200, {
      ok: true,
      pages,
      timesheets_seen: seen,
      timesheets_upserted: timesheetsUpserted,
      line_items_upserted: lineItemsUpserted,
      extra_items_upserted: extraItemsUpserted,
      start: iso(startDate),
      end: iso(endDate),
      modified_after: modifiedAfter,
      version: functionVersion,
    });
  } catch (error) {
    console.error(error);

    if (syncRunId) {
      try {
        await updateSyncRun(syncRunId, {
          finished_at: new Date().toISOString(),
          status: "error",
          error_message: errorMessage(error),
          metadata: {
            version: functionVersion,
            debug_steps: debugSteps.slice(-12),
          },
        });
      } catch (updateError) {
        console.error("Failed to update timesheet sync run", updateError);
      }
    }

    return jsonResponse(500, {
      ok: false,
      error: errorMessage(error),
      sync_run_id: syncRunId,
      debug_steps: debugSteps.slice(-12),
    });
  }
});
