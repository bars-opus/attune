# Graph Report - supabase  (2026-05-24)

## Corpus Check
- 47 files · ~33,594 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 258 nodes · 375 edges · 22 communities (19 shown, 3 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]

## God Nodes (most connected - your core abstractions)
1. `retryFetch()` - 13 edges
2. `redactForLog()` - 12 edges
3. `processWithdrawal()` - 11 edges
4. `PaymentProviderError` - 10 edges
5. `isDebugLogging()` - 9 edges
6. `createSubaccount()` - 8 edges
7. `StripeProvider` - 8 edges
8. `PaystackProvider` - 8 edges
9. `getProvider()` - 8 edges
10. `audit()` - 7 edges

## Surprising Connections (you probably didn't know these)
- `processWithdrawal()` --calls--> `getProvider()`  [EXTRACTED]
  functions/process-withdrawal/index.ts → functions/_shared/providers/registry.ts
- `processWithdrawal()` --calls--> `audit()`  [EXTRACTED]
  functions/process-withdrawal/index.ts → functions/_shared/audit.ts
- `createSubaccount()` --calls--> `isDebugLogging()`  [EXTRACTED]
  functions/paystack-subaccount/index.ts → functions/_shared/sanitize.ts
- `createSubaccount()` --calls--> `redactForLog()`  [EXTRACTED]
  functions/paystack-subaccount/index.ts → functions/_shared/sanitize.ts
- `disconnectSubaccount()` --calls--> `audit()`  [EXTRACTED]
  functions/paystack-subaccount/index.ts → functions/_shared/audit.ts

## Communities (22 total, 3 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.08
Nodes (25): africanCountries, africanCurrencies, authHeader, BookingRequest, corsHeaders, paymentResult, supabase, ValidationResult (+17 more)

### Community 1 - "Community 1"
Cohesion: 0.11
Nodes (23): authHeader, corsHeaders, createBankRecipient(), createMobileMoneyRecipient(), createSubaccount(), disconnectSubaccount(), fetchBanks(), isMobileMoney() (+15 more)

### Community 2 - "Community 2"
Cohesion: 0.15
Nodes (14): PaystackProvider, provider, restore, timingSafeEqualHex(), InitCheckoutInput, InitCheckoutResult, PaymentErrorCategory, PaymentProviderError (+6 more)

### Community 3 - "Community 3"
Cohesion: 0.10
Nodes (17): event, handlePaymentSuccess(), provider, scheduleBookingNotifications(), supabase, PaymentProviderName, err, paystack (+9 more)

### Community 4 - "Community 4"
Cohesion: 0.23
Nodes (13): authHeader, BACKOFF_SCHEDULE_SECONDS, completeWithdrawal(), deadLetterWithdrawal(), failWithdrawal(), getWalletCurrency(), INTERNAL_WEBHOOK_SECRET, nextAttemptAt() (+5 more)

### Community 5 - "Community 5"
Cohesion: 0.14
Nodes (7): StripeProvider, body, header, headers, provider, restore, stripe

### Community 6 - "Community 6"
Cohesion: 0.21
Nodes (13): action, authHeader, corsHeaders, createOAuthLink(), disconnectAccount(), getAccountStatus(), handleOAuthCallback(), json() (+5 more)

### Community 7 - "Community 7"
Cohesion: 0.15
Nodes (12): author, dependencies, @supabase/supabase-js, description, devDependencies, @types/node, license, main (+4 more)

### Community 8 - "Community 8"
Cohesion: 0.15
Nodes (12): author, dependencies, stripe, @supabase/supabase-js, description, keywords, license, main (+4 more)

### Community 9 - "Community 9"
Cohesion: 0.17
Nodes (11): category, channel, corsHeaders, members, notifData, payload, pushJobs, SENDBIRD_WEBHOOK_TOKEN (+3 more)

### Community 10 - "Community 10"
Cohesion: 0.22
Nodes (6): authHeader, corsHeaders, jwt, sendbirdHeaders, supabase, supabaseAdmin

### Community 11 - "Community 11"
Cohesion: 0.25
Nodes (7): dependencies, description, devDependencies, main, name, type, version

### Community 12 - "Community 12"
Cohesion: 0.25
Nodes (5): backoffMinutes, ids, nextAttempt, now, supabase

### Community 13 - "Community 13"
Cohesion: 0.29
Nodes (5): authHeader, corsHeaders, jwt, sbHeaders, supabase

### Community 14 - "Community 14"
Cohesion: 0.33
Nodes (5): deno.enablePaths, deno.lint, deno.unstable, [typescript], editor.defaultFormatter

### Community 15 - "Community 15"
Cohesion: 0.33
Nodes (5): deno.enablePaths, deno.lint, deno.unstable, [typescript], editor.defaultFormatter

### Community 16 - "Community 16"
Cohesion: 0.40
Nodes (3): authHeader, corsHeaders, payload

### Community 17 - "Community 17"
Cohesion: 0.50
Nodes (3): dependencies, stripe, @supabase/supabase-js

### Community 18 - "Community 18"
Cohesion: 0.50
Nodes (3): dependencies, axios, @supabase/supabase-js

## Knowledge Gaps
- **129 isolated node(s):** `name`, `version`, `description`, `main`, `test` (+124 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `redactForLog()` connect `Community 0` to `Community 1`, `Community 3`, `Community 4`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Why does `PaymentProviderError` connect `Community 2` to `Community 0`, `Community 3`, `Community 4`, `Community 5`?**
  _High betweenness centrality (0.022) - this node is a cross-community bridge._
- **Why does `StripeProvider` connect `Community 5` to `Community 2`, `Community 3`?**
  _High betweenness centrality (0.021) - this node is a cross-community bridge._
- **What connects `name`, `version`, `description` to the rest of the system?**
  _129 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08377896613190731 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.11083743842364532 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.10333333333333333 - nodes in this community are weakly interconnected._