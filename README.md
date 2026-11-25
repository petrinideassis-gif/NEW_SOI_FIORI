# NEW_SOI_FIORI

Fiori Elements preview of the Statement of Income (SOI) report (`Y0000CO_SOI_NEW` in `NEW_SOI-AND-PCBUCKE`), built as a RAP custom entity with a query provider class (S/4HANA 2023, OData V4).

Design: [docs/design-note.md](docs/design-note.md).

## Objects in this repository

| Type | Object | File |
|---|---|---|
| Custom entity (line items) | `Y0000CO_C_SOIITM` | `cds/Y0000CO_C_SOIITM.asddls` |
| Custom entity (breakdown) | `Y0000CO_C_SOIDET` | `cds/Y0000CO_C_SOIDET.asddls` |
| Custom entity (SOI lines) | `Y0000CO_C_SOILINE` | `cds/Y0000CO_C_SOILINE.asddls` |
| Query class | `Y0000CO_CL_SOI_QUERY` | `src/classes/Y0000CO_CL_SOI_QUERY.abap` |
| Engine class | `Y0000CO_CL_SOI_ENGINE` | `src/classes/Y0000CO_CL_SOI_ENGINE.abap` |
| Exception class | `Y0000CO_CX_SOI` | `src/classes/Y0000CO_CX_SOI.abap` |
| Service definition | `Y0000CO_UI_SOI` | `service/Y0000CO_UI_SOI.srvd` |

The service binding `Y0000CO_UI_SOI_O4` is created in ADT, not stored here.

No metadata extension: this system does not allow one on a custom entity, so the UI annotations (`@UI.selectionField`, `@UI.lineItem`, `@UI.headerInfo`) are in the custom entity itself.

Stage 3 returns the SOI lines with periods 1-12, the special periods 13-16, the total, and the comparison columns. The engine is a copy of the engine part of `Y0000CO_SOI_NEW` (COSP/COSS via `V_COSP_VIEW` / `V_COSS_VIEW`); the report itself is unchanged. No drill-down yet.

### Old selection screen → Fiori filter bar

| `Y0000CO_SOI_NEW` | Fiori filter | Note |
|---|---|---|
| `P_SOIVAR`, `P_GJAHR`, `P_BUKRS`, `P_VERSN`, `P_WRTTP` | SOI Version, Fiscal Year, Company Code, Version, Value Type | Same defaults (`STD`, `000`, `04`) |
| Total mode (`P_RTOT`) | Period From / Period To left empty | Periods 1-16 |
| Detail mode (`P_RDET`) with `P_PERV` / `P_PERB` | Period From / Period To | Total is the sum of the range; periods outside stay zero |
| `P_GJAHR2`, `P_VERSN2`, `P_WRTTP2` | Comparison Fiscal Year / Version / Value Type | One filled field starts the comparison; blank ones fall back to the main field |
| `P_CMPTO` | Period To | The period range applies to both data sets |

Clicking a SOI line opens its detail page: section **Totals** and section **Breakdown** (the report's double-click drill-down: cost center / order / cost element rows for an extraction line, formula components with operator for a formula line). The breakdown rows add up to the line's total.

Clicking a cost center row of the breakdown opens its detail page with section **Line Items**: the COEP postings (actuals) or COEJ plan rows (exploded per period) for that cost center and cost element over the period range, replacing the report's popup. With a comparison active, the items of both data sets are listed, marked **Base** / **Comparison** in column Data Set. As in the report, order and formula component rows have no line items.

There is no display mode switch: the table always shows total, comparison, periods 01-12 and periods 13-16. In the report, comparison was only allowed in total mode; here it works with any period range.

## Restore order in ADT (one object at a time, activate before the next)

1. Custom entity `Y0000CO_C_SOIITM` (line items): New Data Definition, Ctrl+A, paste, save, activate. It must exist before `Y0000CO_C_SOIDET`, whose association `_Items` points to it
2. Custom entity `Y0000CO_C_SOIDET` (breakdown): New Data Definition, Ctrl+A, paste, save, activate. It must exist before `Y0000CO_C_SOILINE`, whose association `_Details` points to it
3. Custom entity `Y0000CO_C_SOILINE`: New Data Definition (template for custom entity; if none is offered, any template), Ctrl+A, paste, save, activate. A warning that the class does not exist yet is expected
4. Exception class `Y0000CO_CX_SOI`: New ABAP Class, superclass `CX_RAP_QUERY_PROVIDER`, Ctrl+A, paste, fill the header placeholders, save, activate
5. Engine class `Y0000CO_CL_SOI_ENGINE`: New ABAP Class (no interface), Ctrl+A, paste, fill the header placeholders, save, activate
6. Class `Y0000CO_CL_SOI_QUERY`: New ABAP Class, add interface `IF_RAP_QUERY_PROVIDER`, Ctrl+A, paste, fill the header placeholders, save, activate. Then activate the entity once more
7. Service definition `Y0000CO_UI_SOI` (exposes `SOILine`, `SOIBreakdown` and `SOILineItems`), paste, activate
8. Service binding `Y0000CO_UI_SOI_O4`: type OData V4 - UI, on that service definition, activate, publish
9. Run `/IWFND/CACHE_CLEANUP` and `/IWBEP/CACHE_CLEANUP`, then open the preview from the binding (entity set `SOILine`)

All objects go into package `Y0000CO_ALL_OBJECTS`, on one transport request.

## Checks in the preview

1. Filter bar shows version, year, company code, value type, version; the first three are marked mandatory
2. Defaults: version `STD`, value type `04`, version `000`
3. Go with year and company code: the SOI lines of version `STD` appear in outline order with their texts
4. Compare the lines and texts with the classic report `Y0000CO_SOI_NEW` for the same version
5. Totals match `Y0000CO_SOI_NEW` run in total mode for the same version, company code, year, version and value type, line by line
6. Detail: Period From 1, Period To 12 → periods 01-12 and the total match the report in detail mode
7. Comparison: Comparison Version or Fiscal Year filled → Comparison Total, Difference and Difference % match the report in total mode (same values for `P_CMPTO` as Period To)
8. Error message: Period From 10, Period To 3 → error "Periods must be between 1 and 16, and From <= To" instead of an empty table
9. Breakdown: click an extraction line → rows per cost center / order and cost element; their Total adds up to the line's Total and matches the report's drill-down. Click a formula line → its components with operator
10. Line items: in the breakdown of an extraction line, click a cost center row → its line items; their amounts add up to the row's Total and match the report's line item popup

## Troubleshooting (met so far)

| Symptom | Cause | Fix |
|---|---|---|
| "Generic types ... cannot be specified in RETURNING parameters" | RETURNING typed as `standard table of ...` | Named table type `tt_result` |
| "Type Y0000CO_C_SOILINE is unknown" in the class | Entity not active yet | Activate the entity, then the class |
| "Instances of the abstract class CX_RAP_QUERY_PROVIDER cannot be generated" | The class is abstract | Let `CX_RAP_QUERY_FILTER_NO_RANGE` pass through |
| "You wrote a comment outside a method implementation" | Comment between two methods in the implementation part | Comments only inside `method ... endmethod` |
| "INTERFACES IF_T100_DYN_MSG can only be used once" in `Y0000CO_CX_SOI` | `CX_RAP_QUERY_PROVIDER` already implements it | No interface and no constructor in the subclass; both are inherited |
| "Unexpected word annotate" in the data definition | Metadata extension source pasted into the data definition | Paste the `.asddls` into the data definition |
| "Cannot annotate ... type of the annotated entity is not supported" | Metadata extensions are not supported on custom entities in this system | UI annotations directly in the custom entity; no metadata extension |
| "Unexpected character" in the data definition | Text after the closing `}` or an ABAP-style comment (`*`, `"`) | CDS comments are `//` or `/* */`; nothing after `}` |

## Known limits

- Blocking engine errors (wrong period range, company code not in controlling area 2000, no customizing, inconsistent customizing) are shown as an error message. Warnings (a SET that could not be expanded, a formula skipped, no process orders in the SET) appear in the Remark column of the affected lines.
- The authorization check uses `Y0000CO_FI_AUTHORITY_CHECKS` like the report. Its behaviour on a failed check inside an OData request is not verified yet (it may end the request with an error).
- The engine runs once per request; caches do not survive between requests. Opening a breakdown runs the engine again for the whole statement, then builds the breakdown of that line.

## Next stages

Ready for users: transport, Fiori launchpad tile, PFCG role.
