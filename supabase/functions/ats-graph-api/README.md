# ATS Graph API

`index.ts` is the live Supabase Edge Function source for Microsoft Graph email, calendar and Teams interview integration.

The connector used for this repository snapshot clipped very large text payloads, so the exact current `index.ts` bytes are preserved as base64 in:

- `index.ts.b64.part1`
- `index.ts.b64.part2`
- `index.ts.b64.part3`
- `index.ts.b64.part4`

To restore the file locally, concatenate all four files in order and decode from base64:

```powershell
Get-Content .\index.ts.b64.part1, .\index.ts.b64.part2, .\index.ts.b64.part3, .\index.ts.b64.part4 -Raw | Set-Content .\index.ts.b64
[IO.File]::WriteAllBytes("index.ts", [Convert]::FromBase64String((Get-Content .\index.ts.b64 -Raw)))
```

The function exposes routes for health checks, outbound email, interview create/update/cancel, listing locally stored events, syncing Outlook calendar events, and linking unmatched Outlook events to ATS candidates/applications.
