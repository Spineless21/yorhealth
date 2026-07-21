import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-bubble-secret",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

type JsonObject = Record<string, unknown>;

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const bubbleSecret = Deno.env.get("BUBBLE_API_SECRET");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

function jsonResponse(status: number, body: JsonObject) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;

  if (error && typeof error === "object") {
    const maybeError = error as Record<string, unknown>;
    const parts = [
      maybeError.message,
      maybeError.details,
      maybeError.hint,
      maybeError.code,
    ].filter((part) => typeof part === "string" && part.trim().length > 0);

    if (parts.length > 0) return parts.join(" | ");
  }

  try {
    return JSON.stringify(error);
  } catch {
    return "Unknown error";
  }
}

function requireBubbleSecret(req: Request) {
  if (!bubbleSecret) {
    throw new Error("BUBBLE_API_SECRET is not configured");
  }

  const provided = req.headers.get("x-bubble-secret");
  if (!provided || provided !== bubbleSecret) {
    return false;
  }

  return true;
}

async function readJson(req: Request) {
  try {
    return (await req.json()) as JsonObject;
  } catch {
    return {};
  }
}

function requiredString(body: JsonObject, key: string) {
  const value = body[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${key} is required`);
  }

  return value.trim();
}

function optionalString(body: JsonObject, key: string) {
  const value = body[key];
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function normalizeOption(value: string | null) {
  if (!value) return null;

  return value
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function normalizeRightToWork(value: string | null) {
  const cleaned = normalizeOption(value);
  if (!cleaned) return null;
  if (cleaned.includes("sponsor")) return "requires_sponsorship";
  if (cleaned === "yes" || cleaned.startsWith("yes_")) return "yes";
  if (cleaned === "no" || cleaned.startsWith("no_")) return "no";
  return "unknown";
}

function normalizeDrivingLicence(value: string | null) {
  const cleaned = normalizeOption(value);
  if (!cleaned) return null;
  if (cleaned.includes("provisional")) return "provisional";
  if (cleaned === "yes" || cleaned.startsWith("yes_") || cleaned.includes("full")) return "yes";
  if (cleaned === "no" || cleaned.startsWith("no_")) return "no";
  return "unknown";
}

function normalizeVehicleAccess(value: string | null) {
  const cleaned = normalizeOption(value);
  if (!cleaned) return null;
  if (cleaned.includes("sometimes") || cleaned.includes("occasion")) return "sometimes";
  if (cleaned === "yes" || cleaned.startsWith("yes_")) return "yes";
  if (cleaned === "no" || cleaned.startsWith("no_")) return "no";
  return "unknown";
}

function optionalDateTime(body: JsonObject, key: string) {
  const value = optionalString(body, key);
  if (!value) return null;

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function optionalObject(body: JsonObject, key: string) {
  const value = body[key];
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function codeSegment(value: string | null, fallback: string) {
  if (!value) return fallback;

  const cleaned = value
    .toUpperCase()
    .replace(/&/g, " AND ")
    .replace(/[^A-Z0-9\s-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  return cleaned.length > 0 ? cleaned : fallback;
}

function roleCode(value: string | null) {
  const cleaned = codeSegment(value, "JOB");
  const known: Record<string, string> = {
    "SUPPORT WORKER": "SW",
    "CARE WORKER": "CW",
    "TEAM LEADER": "TL",
    "REGISTERED MANAGER": "RM",
    "BRANCH MANAGER": "BM",
    "NURSE MANAGER": "NM",
    "SERVICE CO-ORDINATOR": "SC",
    "SERVICE COORDINATOR": "SC",
    "RGN": "RGN",
  };

  if (known[cleaned]) return known[cleaned];

  const initials = cleaned
    .split(/[\s-]+/)
    .filter(Boolean)
    .map((part) => part[0])
    .join("")
    .slice(0, 4);

  return initials || "JOB";
}

function regionCode(value: string | null) {
  const cleaned = codeSegment(value, "GEN")
    .replace(/^(SL|CC)\s*-\s*/, "")
    .trim();

  const known: Record<string, string> = {
    "MIDLANDS": "MID",
    "NOTTINGHAM": "NOTT",
    "WAKEFIELD": "WAKE",
    "CHESHIRE": "CHESH",
    "OLDHAM": "OLD",
    "DEVON": "DEV",
  };

  if (known[cleaned]) return known[cleaned];

  return cleaned.replace(/[^A-Z0-9]/g, "").slice(0, 5) || "GEN";
}

function vacancyMetadata(body: JsonObject) {
  const metadata: JsonObject = {};
  const bubbleJobId = optionalString(body, "bubble_job_id");
  const pageSlug = optionalString(body, "page_slug");
  const salaryText = optionalString(body, "salary_text");
  const hoursText = optionalString(body, "hours_text");
  const description = optionalString(body, "description");

  if (bubbleJobId) metadata.bubble_job_id = bubbleJobId;
  if (pageSlug) metadata.page_slug = pageSlug;
  if (salaryText) metadata.salary_text = salaryText;
  if (hoursText) metadata.hours_text = hoursText;
  if (description) metadata.description = description;

  return metadata;
}

function vacancyPayload(body: JsonObject, vacancyCode: string) {
  return {
    vacancy_code: vacancyCode,
    title: requiredString(body, "title"),
    job_title: optionalString(body, "job_title"),
    region_name: optionalString(body, "region_name"),
    location_name: optionalString(body, "location_name"),
    employment_type: optionalString(body, "employment_type"),
    status: optionalString(body, "status") ?? "draft",
    metadata: vacancyMetadata(body),
  };
}

async function generateVacancyCode(body: JsonObject) {
  const jobTitle = optionalString(body, "job_title") ?? optionalString(body, "title");
  const regionName = optionalString(body, "region_name") ?? optionalString(body, "location_name");
  const prefix = `${roleCode(jobTitle)}-${regionCode(regionName)}`;

  const { data, error } = await supabase
    .from("ats_vacancies")
    .select("vacancy_code")
    .ilike("vacancy_code", `${prefix}-%`);

  if (error) throw error;

  const maxSequence = (data ?? []).reduce((max, row) => {
    const code = String(row.vacancy_code ?? "");
    const match = code.match(new RegExp(`^${prefix}-(\\d+)$`, "i"));
    if (!match) return max;

    const sequence = Number.parseInt(match[1], 10);
    return Number.isFinite(sequence) && sequence > max ? sequence : max;
  }, 0);

  return `${prefix}-${String(maxSequence + 1).padStart(3, "0")}`;
}

async function findVacancy(body: JsonObject) {
  const vacancyId = optionalString(body, "vacancy_id") ?? optionalString(body, "supabase_vacancy_id");
  const vacancyCode = optionalString(body, "vacancy_code")?.toUpperCase();
  const bubbleJobId = optionalString(body, "bubble_job_id");

  if (vacancyId) {
    const { data, error } = await supabase
      .from("ats_vacancies")
      .select("*")
      .eq("id", vacancyId)
      .maybeSingle();

    if (error) throw error;
    if (data) return data;
  }

  if (vacancyCode) {
    const { data, error } = await supabase
      .from("ats_vacancies")
      .select("*")
      .eq("vacancy_code", vacancyCode)
      .maybeSingle();

    if (error) throw error;
    if (data) return data;
  }

  if (bubbleJobId) {
    const { data, error } = await supabase
      .from("ats_vacancies")
      .select("*")
      .filter("metadata->>bubble_job_id", "eq", bubbleJobId)
      .maybeSingle();

    if (error) throw error;
    return data;
  }

  return null;
}

async function upsertVacancy(body: JsonObject) {
  const existing = await findVacancy(body);
  const suppliedCode = optionalString(body, "vacancy_code")?.toUpperCase();

  if (existing) {
    const { data, error } = await supabase
      .from("ats_vacancies")
      .update(vacancyPayload(body, existing.vacancy_code))
      .eq("id", existing.id)
      .select("*")
      .single();

    if (error) throw error;
    return { vacancy: data, created: false };
  }

  if (suppliedCode) {
    const { data, error } = await supabase
      .from("ats_vacancies")
      .insert(vacancyPayload(body, suppliedCode))
      .select("*")
      .single();

    if (error) throw error;
    return { vacancy: data, created: true };
  }

  for (let attempt = 0; attempt < 5; attempt += 1) {
    const generatedCode = await generateVacancyCode(body);
    const { data, error } = await supabase
      .from("ats_vacancies")
      .insert(vacancyPayload(body, generatedCode))
      .select("*")
      .single();

    if (!error) {
      return { vacancy: data, created: true };
    }

    if (error.code !== "23505") {
      throw error;
    }
  }

  throw new Error("Could not generate a unique vacancy code");
}

async function findCandidate(body: JsonObject) {
  const candidateId = optionalString(body, "candidate_id");
  const bubbleUserId = optionalString(body, "bubble_user_id");
  const email = optionalString(body, "email");

  if (candidateId) {
    const { data, error } = await supabase
      .from("ats_candidates")
      .select("*")
      .eq("id", candidateId)
      .maybeSingle();

    if (error) throw error;
    return data;
  }

  if (bubbleUserId) {
    const { data, error } = await supabase
      .from("ats_candidates")
      .select("*")
      .eq("bubble_user_id", bubbleUserId)
      .maybeSingle();

    if (error) throw error;
    if (data) return data;
  }

  if (email) {
    const { data, error } = await supabase
      .from("ats_candidates")
      .select("*")
      .ilike("email", email)
      .maybeSingle();

    if (error) throw error;
    return data;
  }

  return null;
}

async function upsertCandidate(body: JsonObject) {
  const email = requiredString(body, "email").toLowerCase();
  const bubbleUserId = optionalString(body, "bubble_user_id");
  const rightToWorkUk = normalizeRightToWork(
    optionalString(body, "right_to_work_uk") ?? optionalString(body, "right_to_work"),
  );
  const drivingLicence = normalizeDrivingLicence(optionalString(body, "driving_licence"));
  const accessToVehicle = normalizeVehicleAccess(optionalString(body, "access_to_vehicle"));

  const existing = await findCandidate({ bubble_user_id: bubbleUserId, email });
  const payload = {
    bubble_user_id: bubbleUserId,
    email,
    first_name: optionalString(body, "first_name"),
    last_name: optionalString(body, "last_name"),
    preferred_name: optionalString(body, "preferred_name"),
    phone: optionalString(body, "phone"),
    postcode: optionalString(body, "postcode"),
    source: optionalString(body, "source") ?? "Bubble portal",
    candidate_status: optionalString(body, "candidate_status") ?? "registered",
    right_to_work_uk: rightToWorkUk,
    driving_licence: drivingLicence,
    access_to_vehicle: accessToVehicle,
    relevant_experience: optionalString(body, "relevant_experience"),
    latest_cv_external_url: optionalString(body, "latest_cv_external_url") ?? optionalString(body, "cv_external_url"),
    latest_cv_file_name: optionalString(body, "latest_cv_file_name") ?? optionalString(body, "cv_file_name"),
    consent_to_process: Boolean(body.consent_to_process),
    consent_given_at: body.consent_to_process ? new Date().toISOString() : null,
    sponsorship_required: Boolean(body.sponsorship_required) || rightToWorkUk === "requires_sponsorship",
  };

  if (existing) {
    const { data, error } = await supabase
      .from("ats_candidates")
      .update(payload)
      .eq("id", existing.id)
      .select("*")
      .single();

    if (error) throw error;
    return { candidate: data, created: false };
  }

  const { data, error } = await supabase
    .from("ats_candidates")
    .insert(payload)
    .select("*")
    .single();

  if (error) throw error;
  return { candidate: data, created: true };
}

async function createApplication(body: JsonObject) {
  const candidate = await findCandidate(body);
  if (!candidate) throw new Error("Candidate not found");

  const bubbleApplicationId = optionalString(body, "bubble_application_id");

  if (bubbleApplicationId) {
    const { data: existingByBubbleId, error: existingByBubbleIdError } = await supabase
      .from("ats_applications")
      .select("*")
      .eq("bubble_application_id", bubbleApplicationId)
      .is("archived_at", null)
      .maybeSingle();

    if (existingByBubbleIdError) throw existingByBubbleIdError;
    if (existingByBubbleId) return { application: existingByBubbleId, created: false };
  }

  const vacancy = await findVacancy(body);
  const vacancyId = vacancy?.id ?? optionalString(body, "vacancy_id");

  const screeningSnapshot = optionalObject(body, "screening_snapshot") ?? {
    right_to_work_uk: optionalString(body, "right_to_work_uk") ?? optionalString(body, "right_to_work"),
    driving_licence: optionalString(body, "driving_licence"),
    access_to_vehicle: optionalString(body, "access_to_vehicle"),
    relevant_experience: optionalString(body, "relevant_experience"),
    cv_file_name: optionalString(body, "cv_file_name"),
    cv_external_url: optionalString(body, "cv_external_url"),
  };

  const applicationPayload = {
    bubble_application_id: bubbleApplicationId,
    candidate_id: candidate.id,
    vacancy_id: vacancyId,
    current_stage_key: optionalString(body, "stage_key") ?? "new",
    application_status: optionalString(body, "application_status") ?? "active",
    application_source: optionalString(body, "application_source") ?? optionalString(body, "source") ?? "Careers page",
    application_notes: optionalString(body, "application_notes"),
    recruiter_owner: optionalString(body, "recruiter_owner"),
    applied_at: optionalDateTime(body, "applied_at") ?? new Date().toISOString(),
    submitted_at: optionalDateTime(body, "submitted_at") ?? new Date().toISOString(),
    screening_snapshot: screeningSnapshot,
    metadata: {
      bubble_application_id: bubbleApplicationId,
      bubble_job_id: optionalString(body, "bubble_job_id"),
      vacancy_code: optionalString(body, "vacancy_code"),
      candidate_email: candidate.email,
    },
  };

  const existingQuery = supabase
    .from("ats_applications")
    .select("*")
    .eq("candidate_id", candidate.id)
    .is("archived_at", null);

  const { data: existingApps, error: existingError } = vacancyId
    ? await existingQuery.eq("vacancy_id", vacancyId)
    : await existingQuery.is("vacancy_id", null);

  if (existingError) throw existingError;

  if (existingApps && existingApps.length > 0) {
    const { data, error } = await supabase
      .from("ats_applications")
      .update(applicationPayload)
      .eq("id", existingApps[0].id)
      .select("*")
      .single();

    if (error) throw error;
    return { application: data, created: false };
  }

  const { data, error } = await supabase
    .from("ats_applications")
    .insert(applicationPayload)
    .select("*")
    .single();

  if (error) throw error;
  return { application: data, created: true };
}

async function findApplication(body: JsonObject) {
  const applicationId =
    optionalString(body, "application_id") ?? optionalString(body, "supabase_application_id");
  const bubbleApplicationId = optionalString(body, "bubble_application_id");

  if (applicationId) {
    const { data, error } = await supabase
      .from("ats_applications")
      .select("*")
      .eq("id", applicationId)
      .maybeSingle();

    if (error) throw error;
    return data;
  }

  if (bubbleApplicationId) {
    const { data, error } = await supabase
      .from("ats_applications")
      .select("*")
      .eq("bubble_application_id", bubbleApplicationId)
      .maybeSingle();

    if (error) throw error;
    return data;
  }

  return null;
}

async function disqualifyApplication(body: JsonObject) {
  const application = await findApplication(body);
  if (!application) throw new Error("Application not found");

  const reason = requiredString(body, "reason");
  const notes = optionalString(body, "notes");
  const disqualifiedBy =
    optionalString(body, "disqualified_by") ??
    optionalString(body, "manager_email") ??
    optionalString(body, "bubble_user_id");
  const now = new Date().toISOString();

  const { data: updatedApplication, error: applicationError } = await supabase
    .from("ats_applications")
    .update({
      current_stage_key: "rejected",
      application_status: "rejected",
      decided_at: now,
      decision_reason: reason,
      disqualified_at: now,
      disqualified_by: disqualifiedBy,
      disqualification_reason: reason,
      disqualification_notes: notes,
      disqualification_source: optionalString(body, "source") ?? "Bubble ATS",
      disqualification_metadata: {
        bubble_application_id: application.bubble_application_id,
        previous_stage_key: application.current_stage_key,
        previous_application_status: application.application_status,
        manager_email: optionalString(body, "manager_email"),
        bubble_user_id: optionalString(body, "bubble_user_id"),
      },
    })
    .eq("id", application.id)
    .select("*")
    .single();

  if (applicationError) throw applicationError;

  const { data: stageHistory, error: stageHistoryError } = await supabase
    .from("ats_stage_history")
    .insert({
      candidate_id: application.candidate_id,
      application_id: application.id,
      from_stage_key: application.current_stage_key,
      to_stage_key: "rejected",
      changed_by: disqualifiedBy,
      reason,
      metadata: {
        action: "disqualified",
        notes,
        source: optionalString(body, "source") ?? "Bubble ATS",
      },
    })
    .select("*")
    .single();

  if (stageHistoryError) throw stageHistoryError;

  const { data: note, error: noteError } = await supabase
    .from("ats_notes")
    .insert({
      candidate_id: application.candidate_id,
      application_id: application.id,
      note_type: "disqualification",
      body: notes ? `${reason}\n\n${notes}` : reason,
      visibility: "internal",
      created_by: disqualifiedBy,
      metadata: {
        action: "disqualified",
        stage_history_id: stageHistory.id,
      },
    })
    .select("*")
    .single();

  if (noteError) throw noteError;

  return {
    application: updatedApplication,
    stage_history: stageHistory,
    note,
  };
}

async function createDefaultChecks(body: JsonObject) {
  const candidate = await findCandidate(body);
  if (!candidate) throw new Error("Candidate not found");

  const applicationId = optionalString(body, "application_id");
  const checkTypes = ["dbs", "right_to_work", "identity", "references", "contract"];

  if (candidate.sponsorship_required) {
    checkTypes.push("sponsorship");
  }

  const rows = checkTypes.map((checkTypeKey) => ({
    candidate_id: candidate.id,
    application_id: applicationId,
    check_type_key: checkTypeKey,
    status: "requested",
    required: true,
    requested_at: new Date().toISOString(),
    due_at: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(),
  }));

  const inserted = [];

  for (const row of rows) {
    const existingQuery = supabase
      .from("ats_onboarding_checks")
      .select("*")
      .eq("candidate_id", row.candidate_id)
      .eq("check_type_key", row.check_type_key)
      .eq("is_active", true);

    const { data: existingChecks, error: existingError } = row.application_id
      ? await existingQuery.eq("application_id", row.application_id)
      : await existingQuery.is("application_id", null);

    if (existingError) throw existingError;

    if (existingChecks && existingChecks.length > 0) {
      inserted.push(existingChecks[0]);
      continue;
    }

    const { data, error } = await supabase
      .from("ats_onboarding_checks")
      .insert(row)
      .select("*")
      .single();

    if (error) throw error;
    inserted.push(data);
  }

  return { checks: inserted };
}

async function addDocument(body: JsonObject) {
  const candidate = await findCandidate(body);
  if (!candidate) throw new Error("Candidate not found");

  const documentTypeKey = requiredString(body, "document_type_key");
  const externalUrl = optionalString(body, "external_url");
  const storagePath = optionalString(body, "storage_path");

  if (!externalUrl && !storagePath) {
    throw new Error("external_url or storage_path is required");
  }

  const applicationId = optionalString(body, "application_id");
  let onboardingCheckId = optionalString(body, "onboarding_check_id");

  if (!onboardingCheckId) {
    const checkQuery = supabase
      .from("ats_onboarding_checks")
      .select("id")
      .eq("candidate_id", candidate.id)
      .eq("check_type_key", documentTypeKey)
      .eq("is_active", true);

    const { data, error } = applicationId
      ? await checkQuery.eq("application_id", applicationId).maybeSingle()
      : await checkQuery.maybeSingle();

    if (error) throw error;
    onboardingCheckId = data?.id ?? null;
  }

  const { data: document, error: documentError } = await supabase
    .from("ats_candidate_documents")
    .insert({
      candidate_id: candidate.id,
      application_id: applicationId,
      onboarding_check_id: onboardingCheckId,
      document_type_key: documentTypeKey,
      title: optionalString(body, "title"),
      storage_provider: storagePath ? "supabase" : "bubble",
      storage_path: storagePath,
      external_url: externalUrl,
      bubble_file_id: optionalString(body, "bubble_file_id"),
      file_name: optionalString(body, "file_name"),
      mime_type: optionalString(body, "mime_type"),
      file_size_bytes: typeof body.file_size_bytes === "number" ? body.file_size_bytes : null,
      document_status: "uploaded",
      uploaded_by_bubble_user_id: candidate.bubble_user_id,
      uploaded_at: new Date().toISOString(),
    })
    .select("*")
    .single();

  if (documentError) throw documentError;

  if (onboardingCheckId) {
    const { error: checkError } = await supabase
      .from("ats_onboarding_checks")
      .update({
        status: "submitted",
        submitted_at: new Date().toISOString(),
      })
      .eq("id", onboardingCheckId);

    if (checkError) throw checkError;
  }

  if (documentTypeKey === "cv" || documentTypeKey === "latest_cv") {
    const { error: candidateError } = await supabase
      .from("ats_candidates")
      .update({
        latest_cv_document_id: document.id,
        latest_cv_external_url: externalUrl,
        latest_cv_file_name: optionalString(body, "file_name"),
      })
      .eq("id", candidate.id);

    if (candidateError) throw candidateError;
  }

  return { document };
}

async function getStatus(body: JsonObject) {
  const candidate = await findCandidate(body);
  if (!candidate) throw new Error("Candidate not found");

  const { data: status, error: statusError } = await supabase
    .from("v_ats_candidate_onboarding_status")
    .select("*")
    .eq("candidate_id", candidate.id)
    .single();

  if (statusError) throw statusError;

  const { data: checks, error: checksError } = await supabase
    .from("ats_onboarding_checks")
    .select(
      "id, check_type_key, status, required, requested_at, due_at, submitted_at, verified_at, rejected_at, rejection_reason, expires_on",
    )
    .eq("candidate_id", candidate.id)
    .eq("is_active", true)
    .order("created_at");

  if (checksError) throw checksError;
  return { status, checks };
}

async function enqueueEmpowerSync(body: JsonObject) {
  const candidate = await findCandidate(body);
  if (!candidate) throw new Error("Candidate not found");

  const { data, error } = await supabase
    .from("ats_sync_queue")
    .insert({
      source_system: "supabase",
      target_system: "empower",
      direction: "supabase_to_empower",
      entity_type: "candidate",
      entity_id: candidate.id,
      action: optionalString(body, "action") ?? "create_or_update_worker",
      status: "pending",
      payload: {
        candidate_id: candidate.id,
        email: candidate.email,
        bubble_user_id: candidate.bubble_user_id,
      },
    })
    .select("*")
    .single();

  if (error) throw error;
  return { sync_item: data };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!requireBubbleSecret(req)) {
    return jsonResponse(401, { error: "Unauthorized" });
  }

  try {
    const url = new URL(req.url);
    const path = url.pathname
      .replace(/^\/functions\/v1\/ats-portal-api\/?/, "")
      .replace(/^\/ats-portal-api\/?/, "")
      .replace(/^\//, "");
    const body = req.method === "GET"
      ? Object.fromEntries(url.searchParams.entries())
      : await readJson(req);

    if (req.method === "POST" && path === "candidate/upsert") {
      return jsonResponse(200, await upsertCandidate(body));
    }

    if (req.method === "POST" && path === "vacancy/upsert") {
      return jsonResponse(200, await upsertVacancy(body));
    }

    if (req.method === "POST" && path === "application/create") {
      return jsonResponse(200, await createApplication(body));
    }

    if (req.method === "POST" && path === "application/disqualify") {
      return jsonResponse(200, await disqualifyApplication(body));
    }

    if (req.method === "POST" && path === "onboarding/create-default-checks") {
      return jsonResponse(200, await createDefaultChecks(body));
    }

    if (req.method === "POST" && path === "document/add") {
      return jsonResponse(200, await addDocument(body));
    }

    if ((req.method === "GET" || req.method === "POST") && path === "candidate/status") {
      return jsonResponse(200, await getStatus(body));
    }

    if (req.method === "POST" && path === "sync/enqueue-empower") {
      return jsonResponse(200, await enqueueEmpowerSync(body));
    }

    return jsonResponse(404, {
      error: "Route not found",
      path,
    });
  } catch (error) {
    console.error(error);
    return jsonResponse(400, {
      error: errorMessage(error),
    });
  }
});
