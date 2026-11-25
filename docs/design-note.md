# Design note: SOI report as a Fiori preview

Status: **built and tested in the preview (25.11.2026).** Simplified path as agreed: compatibility views (no ACDOCA), `Y0000CO_SOI_NEW` unchanged (engine copied into `Y0000CO_CL_SOI_ENGINE`), no metadata extensions (not allowed on custom entities here), one period range instead of display modes. Built: SOI lines with periods, total, comparison and remarks; error messages; breakdown (level 2); line items (level 3). The sections below are the original design; where they differ from what was built, the README is current.

Open: authorization test with a user without `F_BKPF_BUK`; timing of a year-over-year comparison; transport, launchpad tile and PFCG role before productive use.
Sources read: `petrinideassis-gif/NEW_SOI-AND-PCBUCKE` (main, `760f516`): `CLAUDE.md`, `src/reports/Y0000CO_SOI_NEW.abap` (3,776 lines), `docs/concept-overview.md`, `docs/change-log.md`, `docs/ddic-spec.md`. `petrinideassis-gif/cost-center-report` (`efb36c6`): `README.md`, `docs/overview.md`, `docs/architecture.md`, `docs/design-decisions.md`, `docs/troubleshooting.md`.

---

## 0. What the reference app teaches

- Cost center report = CDS-only, ACDOCA-based, three-level drill-down through `_CostCenters`, `_Items`, `_CostElements`. Every association carries company code and fiscal year (36 s without it).
- It has no procedural logic: the numbers are plain CDS aggregations. The SOI cannot be built that way. Its lines, sources and formulas come from customizing at run time, and SET expansion is part of the logic.
- Known constraints from that project that apply here too: parameters are not allowed on entities used in service associations; runtime aggregation is not available on 2023; two metadata extensions on one entity break the UI.

## 0a. What the SOI engine really is (from the source)

| Item | Fact | Consequence |
|---|---|---|
| Structure | `lcl_application` mixes engine and screen code (dynpro 0100, CL_SALV grids, popups) | Engine and screen must be split |
| Engine state | ~25 class attributes (`gt_summary`, `gt_order_totals`, caches, `gv_gjahr`, `gv_wrttp` …) | Becomes instance state of an engine class; a stateless OData request will start empty every time |
| Selection coupling | Engine methods read `p_bukrs` (12×), `p_gjahr` (8×), `p_soivar` (9×), `p_versn`, `p_wrttp`, `p_perv/p_perb`, `p_cmpto`, `p_rtot` | Must be replaced by one run-context structure passed in |
| Messages | `MESSAGE e398` in customizing validation (lines 1230–1347) and `MESSAGE s398` warnings in the engine (1536, 2323) | Dialog messages do not work in a query provider: collect them and return them as RAP messages or exceptions |
| Dynpro-only | `leave to screen`, `call screen 0100`, `cl_gui_*`, `cl_salv_*` | Dropped |
| Data sources | `V_COSS_VIEW`, `V_COSP_VIEW` (totals), `COEP`, `COEJ` (line items), `SETLEAF` / `SETHIER` (SET expansion), `CSKS` (names) | Keep the compatibility views in v1 (see Risk 2) |
| Authorization | `check_authority` → `perform authority_f_bkpf_buk in program y0000co_fi_authority_checks` (program is **not** in either repo) | Same call reusable; behaviour on failure is unknown (Risk 3) |

---

## 1. Target structure

**Recommendation: custom entities with an `IF_RAP_QUERY_PROVIDER` implementation, one per level, plus a read-only root query that runs the engine once per request.**

Why not a CDS-only design (like the cost-center app)?
- The line structure, the sources and the formulas are customizing. CDS would need one view per SOI version and a hand-written UNION per line, and the formula lines (METHOD R, dependency-ordered in passes) cannot be expressed in CDS at all.
- SET expansion (cost center groups, cost element groups, process order SET) and the order batching with halving on `DBSQL_STMNT_TOO_LARGE` are procedural.

Why custom entities rather than a classic RAP BO with a query implementation?
- There is no transactional need (read only), so no behaviour definition is wanted (per the skill: a BDEF makes the service transactional and conflicts with the runtime aggregation pattern).
- Custom entities give exactly one hook: the query provider class. Associations between custom entities are supported; to verify on the target system (Risk 4).

Objects (proposed names, all ≤30 characters, `Y0000CO_` prefix):

| # | Object | Type | Role |
|---|---|---|---|
| 1 | `Y0000CO_C_SOILINE` | Custom entity (root) | One row per SOI line for the selected run. Level 1. |
| 2 | `Y0000CO_C_SOIBRK` | Custom entity (child) | Extraction breakdown: cost center / order / cost element rows (METHOD C/A). Level 2. |
| 3 | `Y0000CO_C_SOIFRM` | Custom entity (child) | Formula components (METHOD R, from `Y0000CO_NSOI03`). Level 2. |
| 4 | `Y0000CO_C_SOIITM` | Custom entity (child) | Line items from COEP (actual) and COEJ (plan). Level 3. |
| 5 | `Y0000CO_CL_SOI_QUERY` | Global class, `IF_RAP_QUERY_PROVIDER` | Thin adapter: maps the request to the engine, builds the result rows, handles `$top`/`$skip`/`$orderby` in memory. |
| 6 | `Y0000CO_CL_SOI_ENGINE` | Global class | Engine, moved out of `lcl_application`. No screen, no `p_*`. |
| 7 | `Y0000CO_C_SOILINE` (metadata extension) | Metadata extension | Filter bar, columns, facets. Layer `#CUSTOMER`. |
| 8 | `Y0000CO_UI_SOI` | Service definition | Exposes 1–4. |
| 9 | `Y0000CO_UI_SOI_O4` | Service binding | OData V4 - UI. |

Naming note: the company convention (`abap-conventions`) describes local classes in reports (`lcl_application`). Global classes `Y0000CO_CL_*` are required by RAP, so this is a convention gap. **Decision needed:** accept `Y0000CO_CL_*` for the two engine classes, or keep them as local classes inside a global shell (not recommended).

Keys (all custom entities): `SoiVersion`, `FiscalYear`, `CompanyCode`, `ValueType`, `Version`, `SoiLine` (root). Child keys carry the parent key plus a row key (`CostCenter` / `Order` / `CostElement`, or `CalcLine`, or `PostingDocument` + item).

---

## 2. Filters and parameters

Single filter bar on the root. Child entities inherit the parent's filter values through their keys; they take no filter of their own.

| Field | Type | Mandatory | Default | Maps from | Notes |
|---|---|---|---|---|---|
| `SoiVersion` | CHAR 4, value help on `Y0000CO_NSOI00` | Yes | `STD` | `p_soivar` | Also drives every customizing read |
| `FiscalYear` | GJAHR | Yes | none | `p_gjahr` | |
| `CompanyCode` | BUKRS, standard company code value help (**name to verify in ADT**, Ctrl+Shift+A `*CompanyCode*VH*`; not guessed) | Yes | none | `p_bukrs` | Authorization anchor (section 6) |
| `Version` | VERSN | No | `000` | `p_versn` | |
| `ValueType` | WRTTP | No | `04` | `p_wrttp` | Validation warning when not `04`/`000` (today: `W` message) |
| `PeriodFrom` / `PeriodTo` | MONAT | Only in detail mode | `01` / `12` | `p_perv`, `p_perb` | Range. Not a CDS parameter (the cost-center app dropped parameters for this reason). Use a plain filter with range semantics, tested in preview. |
| `DisplayMode` | CHAR 1 (`D` detail / `T` total) | No | `T` | `p_rdet` / `p_rtot` | Default **total** for the first slice. |
| `FiscalYear2` | GJAHR | No | = `FiscalYear` | `p_gjahr2` | Comparison triple, total mode only |
| `Version2` | VERSN | No | = `Version` | `p_versn2` | Same |
| `ValueType2` | WRTTP | No | = `ValueType` | `p_wrttp2` | Same |
| `ComparePeriod` | MONAT | No | = `12` (cap) | `p_cmpto` | Caps both sides at the same period |

Rules to keep (from the report):
- Comparison only in total mode. In detail mode, a filled comparison field is an error, not a silent ignore.
- Blank comparison field falls back to the main field.
- Detail mode honours the period range. Total mode always covers periods 1–16.
- `FiscalYear2` equal to `FiscalYear` with same version and value type gives all-zero differences: keep the warning.
- Controlling area fixed to `'2000'`; ledger `'00'` as in `gc_lednr` (to confirm the code value).

---

## 3. Drill-down

| Level | Root row kind | Child entity | Source in the engine | Key |
|---|---|---|---|---|
| 1 | SOI line (extraction, METHOD C/A) | `_Breakdown` → `Y0000CO_C_SOIBRK` | `collect_cc_detail`, `collect_order_detail`, `merge_detail_object` | `SoiLine` + object |
| 1 | SOI line (formula, METHOD R) | `_Components` → `Y0000CO_C_SOIFRM` | `build_detail_formula` | `SoiLine` + `CalcLine` |
| 2 | Breakdown row for a cost center | `_LineItems` → `Y0000CO_C_SOIITM` | `read_line_items_coep` / `_coej` (scoped to object + KSTAR + period) | object + cost element + period |

- The breakdown keeps the reconciliation rule: unsigned values, period columns follow the grid, periods outside the range are zero.
- Formula components show unsigned values with the operator as a separate field (as today).
- The third level replaces the popup. A Fiori object page with a line-item table (`#LINEITEM_REFERENCE`) is the target. The cost-center app already proves that pattern.
- Association keys: every association repeats company code and fiscal year, as the cost-center app does (the `_Items` lesson). With custom entities this is a correctness requirement for the query provider: the child query needs the parent's full key to know what to recompute or read.

---

## 4. What reuses the engine, what changes, what is dropped

**Reuse as-is (pure ABAP, no screen coupling, after the context change in 4a):**
`read_customizing`, `validate_customizing`, `get_set_values`, `resolve_cc_by_group_bukrs`, `build_objnr_from_costcenters`, `resolve_kstar_group`, `prepare_order_scope` (logic only), `read_order_totals`, `read_order_totals_batch` (halving logic kept unchanged), `periods_from_wog`, `accumulate_periods`, `add_periods_to_summary`, `select_totals_for_rule`, `prepare_rule_scopes`, `build_summary_data`, `apply_formula_lines`, `build_comparison`, `read_currency`, `read_line_items_coep`, `read_line_items_coej`, `collect_order_detail`, `collect_cc_detail`, `merge_detail_object`, `decode_objnr`, `build_detail_formula`, `compute_detail_diffs`, `diff_percent`, `sum_periods_in_range`, `enrich_detail_texts`, `get_cached_*`.

**Refactor (coupled to the screen or to `p_*`/`gv_*` globals):**
- `validate_selection_screen`, `modify_screen`, `is_compare_requested`, `compare_*`, `help_wrttp`, `determine_period_bounds` → rules move into the query provider and return RAP exceptions / messages.
- `run`, `run_pass`, `set_run_context`, `reset_value_caches` → become the engine's public `run( is_context )` with the context structure (SoiVersion, FiscalYear, CompanyCode, Version, ValueType, Period range, comparison set, DisplayMode). `gv_*` become instance attributes of the engine.
- `read_customizing` / `validate_customizing` / `prepare_order_scope` / `apply_formula_lines` / `collect_*` messages → collect into a message table (`MESSAGE s/e` today).
- `set_line_item_texts`, `set_detail_texts` → texts go into the result rows (no ALV field catalogue).

**Dropped (no Fiori equivalent):**
`build_controls`, `display_alv`, `display_detail`, `display_line_items`, `on_double_click`, `on_detail_double_click`, `set_col_*`, `set_month_text`, `set_compare_texts`, `set_detail_texts`, `show_line_items` (popup), the splitter, the `cl_salv_*` objects, the module pool (`status_0100`, `user_command_0100`, `exit_command_0100`), dynpro 0100 and its screen text.

Column visibility (today `set_col_visible`, `set_col_pos`) moves to `@UI.lineItem` in the metadata extension. Totals (today `set_col_sum`) do **not** move to `@Aggregation.default`: a custom entity has no SQL, so the query class must return finished totals (see 8b).

### 4a. The context change (the central refactor)

The engine today reads its inputs from `p_*` and from class attributes that the run sets. The refactor is mechanical but touches many lines, so the first commit must be **behaviour-neutral**: the report `Y0000CO_SOI_NEW` keeps working, and the engine is first moved into `Y0000CO_CL_SOI_ENGINE` with the same logic and a context structure. Only after that does the query provider appear. The report can then call the engine as well, which gives a tie-out for free (section 9).

---

## 5. Performance

The engine was tuned on ST05 traces inside a report. Inside a stateless OData request, the assumptions change:

1. **Memory across requests.** Drill-down today reads `gt_order_totals` and `gt_summary_a`, which are in memory from the root run. An OData child request is a new request, and the work process may differ. Options:
   - **A. Recompute per request.** Simple, correct. Cost: `read_order_totals` on every child call. Acceptable only if measured.
   - **B. Persist the run.** Root query writes the run result to a DB table (`Y0000CO_SOIRUN`, keyed by a run id and the user, with a timestamp), children read it back. No recompute; needs cleanup.
   - **C. Shared memory (`CL_SHM_AREA`).** Fast, but lifetime and invalidation are harder; not recommended for v1.
   **Recommendation:** A for the first slice (total mode, root only, no children). Decide B before the drill-down slice, based on the measured cost of A.
2. **One SET expansion per request.** The cost center group, cost element group and process order SET must be expanded once per root request, not once per row or per child. The engine already caches these; the query provider must call it once and keep the result for the request. SETs are expanded without a key date (today's groups), which is intentional and must stay so.
3. **Order batching.** `read_order_totals_batch` with halving stays as it is. The root returns a few dozen SOI lines, so `$top`/`$skip` are applied in memory after the run; no paging over the database.
4. **Plan vs actual.** A plan pass skips orders and METHOD A rules (existing behaviour). Keep it: a comparison against plan costs less than a comparison against a previous year.
5. **Year-over-year** remains the expensive case. Flag it in the preview; do not optimise in v1.

---

## 6. Authorization

The report calls `authority_f_bkpf_buk` (`F_BKPF_BUK`, activity `03`) first in `run( )`. In a RAP service, a DCL does not help with a custom entity's query results, so the check has to be in the query provider.

Proposal:
- In `Y0000CO_CL_SOI_QUERY->if_rap_query_provider~select`, the first statement calls the same check with `CompanyCode` and activity `03`, via the same PERFORM in `y0000co_fi_authority_checks`. One check, one place, the same behaviour as the report.
- Child entities call the same check (the company code is in their key).
- A failed check must raise a RAP exception (`cx_rap_query_provider` or a custom one), never a dialog message.
- No DCL on the custom entity, in v1 **and** for production. The skill's production path (a DCL role on `CompanyCode` replacing `#NOT_REQUIRED`) is for CDS view entities; it does not apply to a custom entity, so the query-class check is the permanent control. Still needed before productive use: launchpad tile, PFCG role with the business catalog.

**Blocker:** the content of `y0000co_fi_authority_checks` is not in either repository. I cannot tell whether `authority_f_bkpf_buk` raises a message or a dump when unauthorised. Needed from you (Risk 3).

---

## 7. First slice (proposed)

One read-only root entity in **total mode only**, one version and one fiscal year, verified in the preview before anything else is added:

- Engine moved to `Y0000CO_CL_SOI_ENGINE` (behaviour-neutral, section 4a) and the classic report still green.
- `Y0000CO_C_SOILINE` root with: `SoiVersion`, `FiscalYear`, `CompanyCode`, `Version`, `ValueType` as filters, default `STD` / `04` / `000`.
- Columns: SOI line text and number, outline, total, company code currency.
- No comparison, no periods, no drill-down, no line items.
- Authorization check in place.
- Acceptance: the totals in the preview match the classic report, run in SAP GUI in total mode for the same selection, line by line.

Second slice (after the first is verified): detail mode with periods; third: comparison; fourth: drill-down (choose the persistence option from section 5); fifth: line items.

---

## 8. Steps you must do in ADT on the system

For the first slice:

1. Import the engine as a global class `Y0000CO_CL_SOI_ENGINE` (I will write the source in the repo; you create the class in ADT, paste, activate).
2. Create the query provider class `Y0000CO_CL_SOI_QUERY` (`IF_RAP_QUERY_PROVIDER`) and activate.
3. Create the custom entity `Y0000CO_C_SOILINE` (ADT: New Data Definition → *Custom Entity*, bound to the query class) and activate.
4. Create the metadata extension `Y0000CO_C_SOILINE` with the same name (only one per entity — cost-center lesson).
5. Create the service definition `Y0000CO_UI_SOI` (expose the root as `SOILine`), activate.
6. Create the service binding `Y0000CO_UI_SOI_O4` (OData V4 - UI) on that service definition, activate, publish.
7. Run `/IWFND/CACHE_CLEANUP` and `/IWBEP/CACHE_CLEANUP` before the first preview (cost-center lesson). If publish fails with an authorization message, it is gateway authorization: Basis or `/IWFND/V4_ADMIN`; send me the exact message.

One object at a time: create, save (Ctrl+S), activate (Ctrl+F3), report "active" (or the Problems-tab error), then the next. Package: `$TMP` for the throwaway stub stage (no transport), the real package plus a transport once the plumbing works — your call.
8. Preview from the binding. Compare totals with `Y0000CO_SOI_NEW` in SAP GUI (total mode, same selection).
9. Check the authorization: once with a user that has `F_BKPF_BUK` for the company code, once without.

Not needed for this slice: launchpad tile, PFCG role, DCL. Those come before productive use.

---

## 8a. Walkthrough: a custom entity in ADT

Menu names below are from the standard ADT layout. I cannot open ADT from here, so **wording and template names must be confirmed on your system** (they differ slightly between ADT versions).

**What the pieces are (classic ABAP analogy)**

| Object | Analogy |
|---|---|
| Custom entity | A structure type (fields and keys) with the annotation that says which class fills it |
| Query class | A function module returning an internal table, called by the framework |
| Metadata extension | ALV field catalogue and selection screen layout |
| Service definition | The list of what is published |
| Service binding | The transaction code |

**Step 1: query class `Y0000CO_CL_SOI_QUERY`** (create first so the entity can name it)
1. Right-click the package → New → ABAP Class.
2. Name `Y0000CO_CL_SOI_QUERY`, add interface `IF_RAP_QUERY_PROVIDER`, finish.
3. The editor shows the class with an empty method `if_rap_query_provider~select`. Save (Ctrl+S), activate (Ctrl+F3). Empty is fine at this point.

**Step 2: custom entity `Y0000CO_C_SOILINE`**
1. Right-click the package → New → Other ABAP Repository Object → Core Data Services → Data Definition.
2. Name `Y0000CO_C_SOILINE`. In the template list pick the one named *Custom Entity* (if none is offered, choose the empty template and type the source by hand).
3. The editor shows a header annotation and a field list. The shape is:
   - Header annotation `@ObjectModel.query.implementedBy: 'ABAP:Y0000CO_CL_SOI_QUERY'`: this is the link to the class.
   - `define root custom entity Y0000CO_C_SOILINE { key ...; ... }`: keys first, then the fields with their types (`abap.char(4)`, `abap.numc(5)`, `abap.curr(15,2)` with `@Semantics.amount.currencyCode`, etc.).
4. Activate. Errors appear in the Problems tab. A custom entity activates without the class doing anything yet, so you can check the field list on its own.

**Step 3: the query class body** (this is the part that needs code; I will write it only after you approve the design)
- `io_request->is_data_requested( )` tells you the call wants rows.
- `io_request->get_filter( )->get_as_ranges( )` gives the filter-bar values; this is where `SoiVersion`, `FiscalYear`, `CompanyCode` come in.
- `io_request->get_paging( )` and `get_sort_elements( )` give `$top`, `$skip`, `$orderby`; the class applies them in memory.
- `io_response->set_data( lt_rows )` and `set_total_number_of_records( )` return the result.
- The engine call and the authorization check go here, authorization first.

**Step 4: metadata extension, service definition, service binding** (same as the cost-center app)
- Metadata extension: same name as the entity, `@UI.selectionField`, `@UI.lineItem`, `@UI.headerInfo`, layer `#CUSTOMER`. Mandatory filters are marked there (`@Consumption.filter.mandatory: true`). One extension per entity.
- Service definition `Y0000CO_UI_SOI`: `expose Y0000CO_C_SOILINE as SOILine;`.
- Service binding `Y0000CO_UI_SOI_O4`: type *OData V4 - UI*, activate, publish, preview.

**What you will notice compared with the cost-center app**
- ADT Data Preview (F8) on the entity does not work, because there is no SQL behind it. Test through the service binding preview.
- No automatic sorting, filtering or aggregation: whatever the class does not apply is not applied.
- Value helps and texts are not joined in CDS; the class fills text fields (for example the SOI line text) in the rows.

---

## 8b. Alignment with the `abap-rap-fiori-report` skill

Checked each rule of the skill against this design.

| Skill rule | Effect on the design |
|---|---|
| 1. Never state a standard view name unverified | One name in the first draft (`I_CompanyCode`) was unverified. Replaced by "find in ADT". Rule applies to every standard value help and text view added later (cost center names, cost element names) |
| 2. Read CO actuals from ACDOCA, ledger `0L`, company code currency | Differs from the engine, which reads `V_COSS_VIEW` / `V_COSP_VIEW` / COEP / COEJ. Kept for v1 so numbers tie to the classic report (decision 4 stays open). The skill supports the ACDOCA route later; facts to carry over: ledger filter is mandatory there, object currency is not filled, `HSL` equals the WOG values for cost centers. Plan is a different source (`WRTTP`-based COSP/COSS today, `ACDOCP` + `PLAN_0` in the cost-center app) and would need its own tie-out |
| 3. Base view → consumption view → MDE → service definition → binding; no behavior definition | Followed. No BDEF. A custom entity replaces the base+consumption pair, because there is no SQL source to put in a base view. The value help view `Y0000CO_SOIVARVH` is the only view entity |
| 4. Texts by left outer join, `@ObjectModel.text.element` | No joins in a custom entity. The class fills text fields; `@ObjectModel.text.element` stays on the key element so Fiori shows "Key (Text)". One-row-per-key rule applies to the class (language fallback of `Y0000CO_NSOI01T`) |
| 5. Runtime aggregation with `@Aggregation.default`, drill-down by adding columns | **Does not apply** to a custom entity (no SQL). Also, the cost-center repo records that runtime aggregation is not available on this 2023 system, which contradicts the skill's claim; the repo is the more recent evidence. Totals and subtotals are computed by the engine, and drill-down is by associations (section 3), not by gear-icon column splitting. Expect the preview to show a plain table |
| 6. Validate numbers against SAP GUI | Section 7 already ties to `Y0000CO_SOI_NEW`. Add a second check on one cost center / period against KSB1 or S_ALR_87013611 |
| Execution and deployment | Publish authorization, cache cleanup and productive requirements added to section 8 and section 6 |
| How to guide | One object at a time, wait for "active", Problems tab. Added to section 8. Source is regenerated in full, not patched |

---

## 9. Risks and open questions

1. **Stateless drill-down** (section 5, option A vs B). Decide before slice 4.
2. **Compatibility views.** The engine reads `V_COSS_VIEW` / `V_COSP_VIEW`. The cost-center app reads ACDOCA. The SOI numbers must tie to the classic report, so the compatibility views stay in v1. Question: do you want to move the engine to ACDOCA later (the reference project's approach), knowing the numbers would then need a tie-out per version?
3. **Authority program is not in the repos.** Need `y0000co_fi_authority_checks` (or its `authority_f_bkpf_buk` form) to confirm its failure behaviour.
4. **Associations between custom entities** on 2023 with the query provider: to verify on the system with a throwaway child before committing to slice 4.
5. **Period range as a filter.** Multi-value range semantics in the filter bar need a check in preview; fallback is two fields (from/to), as today.
6. **Messages in the engine.** Warnings (`MESSAGE s398` for skipped formulas, missing orders) need a home in the response (RAP messages). Decide the format; the simplest is one message table per response.
7. **Language.** SOI line texts use a language fallback (`01T`). The result rows must carry the same fallback; confirm the logon language of the preview user.
8. **Repo drift.** The design assumes the repo source equals the source running in the system. Confirm the transport state before importing the engine.
9. **Naming / convention gap.** Global classes `Y0000CO_CL_*` (section 1).
10. **Out of scope:** `Y0000CO_SOI_COPY`, `Y0000CO_SOI_DDIC_CREATE`, `Y0000CO_PCBUCKE`, the copy of customizing, AFC integration (the report is a display report by decision).

Not touched, per your instruction: `petrinideassis-gif/sap-co-reports` (duplicate, to remove in GitHub settings), `petrinideassis-gif/sap_abaper` (decision pending).

---

## 10. Decisions I need from you

1. Custom entity + query provider (section 1), or do you prefer a different target?
2. Persistence option for drill-down (A or B, section 5) — decide later is fine.
3. Global classes `Y0000CO_CL_*` accepted despite the report-only convention?
4. Keep the compatibility views in v1 (recommended) or go to ACDOCA?
5. Provide `y0000co_fi_authority_checks` source.
