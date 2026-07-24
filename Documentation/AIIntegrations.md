# Optional AI integrations

Checked against official provider documentation on 2026-07-14. Quotas, model availability, regional availability, and terms can change; recheck the linked provider pages before production deployment.

## Recommendation

Use Cloudflare Workers AI for the first optional server-side feature because the provider proxy already runs as a Cloudflare Worker. The checked-in adapter uses an `AI` binding rather than a credential in the iOS application. Keep Apple Foundation Models as a future on-device enhancement for compatible devices, not as a universal dependency.

## Auto model selection

The same provider boundary can support an `Auto` model selector for explanation, OCR assistance, summarization, or research drafting. It cannot replace the deterministic layover and entry engines, and it cannot select a generative model as an immigration, boarding, or connection authority.

The selector should receive a task class, privacy tier, offline allowance, maximum cost, latency target, minimum quality/reasoning score, and required capabilities. A versioned model catalog should supply each candidate's provider, capabilities, context limit, current price metadata, measured latency percentiles, availability/quota state, license, retention/training policy, and fallback models. Pricing and quotas are refreshed metadata, never hidden constants.

Selection is constrained first, then ranked over the non-dominated candidates:

```text
eligible = capability AND privacy AND context AND budget AND availability
frontier = Pareto(cost, p95 latency, evaluated task quality)
choice = lexicographic(user mode, frontier, stable model ID)
```

Supported modes can be `Auto`, `Fast`, `Balanced`, `Deep reasoning`, `Private/offline`, and `Budget capped`. Each result should include a selection trace, estimated cost, latency evidence, rejected-candidate reasons, and an outage fallback. The same catalog snapshot and request revision must replay to the same choice; live quota, price, and outage changes may legitimately change a later choice.

This is an app architecture feature, not a control over the model serving this Codex conversation. I can adapt response depth and tool use, but the workspace cannot force a Codex model change.

The implemented AI capability is deliberately narrow:

- `POST /v1/ai/explain` accepts either a sourced calculation trace or sourced facility records.
- The model sees fact identifiers and short descriptors, not operational values, provider record identifiers, URLs, or traveler profile fields.
- The model may only order every fact identifier exactly once and choose a presentation focus from an enum.
- Deterministic Worker code renders every value, formula, provenance record, opening-hours string, and URL from validated request data.
- Raw model prose is never returned. Missing, duplicate, added, or malformed identifiers trigger the original deterministic order.
- The route rejects visa, passport, nationality, citizenship, immigration, and entry-requirement content before inference.
- The response explicitly reports that AI cannot change feasibility, decide entry requirements, or override `SafetyPolicy`.
- Requests and responses are `no-store`, and AI output is not authorized for native-model training.

This is less expressive than an unconstrained chatbot, but it makes the safety boundary enforceable in code rather than relying only on a prompt.

## Current provider comparison

| Option | Current free access | Data/key posture | Fit for Airport XR Companion |
|---|---|---|---|
| Cloudflare Workers AI | The Free and Paid Workers plans currently receive 10,000 neurons per day at no charge; Free-plan inference stops after the allocation. Model-specific consumption applies and resets at 00:00 UTC. | A Worker binding exposes `env.AI`; no provider API key is shipped to iOS. Cloudflare says Workers AI customer content is not used to train models or improve Cloudflare/third-party services without explicit consent. Model-specific licenses still apply. | Recommended server adapter. It reuses the existing authenticated proxy and rate limiter. [Pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) · [binding](https://developers.cloudflare.com/workers-ai/configuration/bindings/) · [data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/) |
| Google Gemini Developer API | New projects can start on a Free Tier for selected models, but active RPM/TPM/RPD limits are model- and project-specific and must be checked in AI Studio; published limits are not guaranteed. | Requires an API key, which would belong in a Worker secret. Under the current unpaid-service terms, Google may use inputs and outputs to improve products and human reviewers may process them; Google says not to submit sensitive, confidential, or personal information. Regional and client-use restrictions also apply. | Do not use the unpaid tier for traveler-specific production prompts. A future paid adapter could process only the same minimized fact descriptors after legal/privacy review. [Billing](https://ai.google.dev/gemini-api/docs/billing) · [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) · [terms](https://ai.google.dev/gemini-api/terms) |
| Hugging Face Inference Providers | Free Hub users currently receive $0.10 in monthly inference credits, expressly subject to change; extra use requires purchased credits. | Requires a fine-grained Hugging Face token with Inference Providers permission. The routed inference provider and model must be reviewed separately. | Useful for experiments and provider portability, but the starter credit is too small to be the primary passenger-facing path. [Pricing](https://huggingface.co/docs/inference-providers/en/pricing) · [getting started](https://huggingface.co/docs/inference-providers/en/index) |
| Apple Foundation Models | The framework uses the model included with Apple Intelligence rather than a metered web API. | No app API key; supported tasks can remain on-device and work offline. Availability depends on Apple Intelligence being enabled on a supported device/region, and the device-scale model is not intended for world knowledge or advanced reasoning. | Best future privacy/offline enhancement for explanation and summarization on compatible devices. It cannot replace sourced APIs or the deterministic engine, and the app’s iOS 18 baseline requires an availability-gated implementation. [Framework](https://developer.apple.com/documentation/foundationmodels/) · [Apple overview](https://developer.apple.com/videos/play/wwdc2025/286/) |

The Cloudflare allocation is a free allowance, not a permanent capacity guarantee. Production should enforce a dedicated route budget below the provider quota and return the deterministic trace unchanged when AI is unavailable or exhausted.

## Configuration

`Backend/wrangler.toml` contains the non-secret binding:

```toml
[ai]
binding = "AI"
```

No new API key is required for the implemented Cloudflare adapter. Cloudflare documents that even local Workers AI calls reach the account and consume usage, so deterministic tests mock `env.AI.run` and make no live inference calls.

If a future adapter is approved, keep its credential in Worker secrets only:

```bash
cd Backend
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put HUGGINGFACE_TOKEN
```

Neither name is read by the current Worker; do not provision unused secrets. The iOS app continues to receive only the HTTPS proxy URL through ignored `Secrets.xcconfig`.

## Request contract

Calculation-trace example:

```json
{
  "task": "explainCalculationTrace",
  "locale": "en",
  "trace": {
    "title": "HND connection calculation",
    "revision": "snapshot-44",
    "policyVersion": "safety-policy-v3",
    "inputs": [
      {
        "label": "Terminal route",
        "value": 17,
        "unit": "min",
        "provider": "terminal graph",
        "providerField": "route.durationMinutes",
        "sourceRecord": "route-105",
        "observedAt": "2026-07-14T10:00:00Z",
        "receivedAt": "2026-07-14T10:00:02Z"
      }
    ],
    "steps": [
      {
        "label": "Available window",
        "formula": "onward gate close - inbound on block",
        "result": 43,
        "unit": "min",
        "sourceReferences": ["flight-leg-1", "flight-leg-2"]
      }
    ],
    "caveats": ["Queue time is unknown."]
  }
}
```

Facility input accepts only `name`, `category`, `accessZone`, optional `terminal`, sourced hours/status, an HTTPS official record, source provider, and timestamps. It does not accept free-form prompts or descriptions.

The response contains an ordered `explanation.facts` array plus the model role, policy version, source metadata, and machine-readable safeguards. Clients must render the facts as advisory explanation and retain the original deterministic decision from `CalculationTrace`.

## Verification and rollout

```bash
cd Backend
npm test
npm run check
npx wrangler deploy --dry-run
```

Deterministic tests cover missing bindings, strict schemas, prohibited entry domains, unknown values, grounded calculation/facility rendering, malformed model output, provider failure, no raw model-output exposure, no training authorization, and the all-facts-preserved invariant. A credentialed live smoke test is opt-in and must never gate CI or log request/model payloads.

Before enabling an iOS affordance:

1. Map only the already-built `CalculationTrace` or normalized facility records into this request schema.
2. Do not include traveler profile fields, user notes, precise location history, or provider payloads.
3. Treat `503`, `502`, and `429` as “AI explanation unavailable” and display the original deterministic trace.
4. Keep the existing live/demo/offline badge. AI availability is not evidence that operational data is live.
5. Recheck the selected model license, Cloudflare quota, and data terms at release time.
