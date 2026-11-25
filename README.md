# NEW_SOI_FIORI

Fiori Elements preview of the Statement of Income (SOI) report (`Y0000CO_SOI_NEW` in `NEW_SOI-AND-PCBUCKE`), built as a RAP custom entity with a query provider class (S/4HANA 2023, OData V4).

Design: [docs/design-note.md](docs/design-note.md).

## Objects in this repository

| Type | Object | File |
|---|---|---|
| Custom entity | `Y0000CO_C_SOILINE` | `cds/Y0000CO_C_SOILINE.asddls` |
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

There is no display mode switch: the table always shows total, comparison, periods 01-12 and periods 13-16. In the report, comparison was only allowed in total mode; here it works with any period range.

## Restore order in ADT (one object at a time, activate before the next)

1. Custom entity `Y0000CO_C_SOILINE`: New Data Definition (template for custom entity; if none is offered, any template), Ctrl+A, paste, save, activate. A warning that the class does not exist yet is expected
2. Exception class `Y0000CO_CX_SOI`: New ABAP Class, superclass `CX_RAP_QUERY_PROVIDER`, Ctrl+A, paste, fill the header placeholders, save, activate
3. Engine class `Y0000CO_CL_SOI_ENGINE`: New ABAP Class (no interface), Ctrl+A, paste, fill the header placeholders, save, activate
4. Class `Y0000CO_CL_SOI_QUERY`: New ABAP Class, add interface `IF_RAP_QUERY_PROVIDER`, Ctrl+A, paste, fill the header placeholders, save, activate. Then activate the entity once more
5. Service definition `Y0000CO_UI_SOI`, paste, activate
6. Service binding `Y0000CO_UI_SOI_O4`: type OData V4 - UI, on that service definition, activate, publish
7. Run `/IWFND/CACHE_CLEANUP` and `/IWBEP/CACHE_CLEANUP`, then open the preview from the binding (entity set `SOILine`)

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

## Troubleshooting (met so far)

| Symptom | Cause | Fix |
|---|---|---|
| "Generic types ... cannot be specified in RETURNING parameters" | RETURNING typed as `standard table of ...` | Named table type `tt_result` |
| "Type Y0000CO_C_SOILINE is unknown" in the class | Entity not active yet | Activate the entity, then the class |
| "Instances of the abstract class CX_RAP_QUERY_PROVIDER cannot be generated" | The class is abstract | Let `CX_RAP_QUERY_FILTER_NO_RANGE` pass through |
| "You wrote a comment outside a method implementation" | Comment between two methods in the implementation part | Comments only inside `method ... endmethod` |
| "Unexpected word annotate" in the data definition | Metadata extension source pasted into the data definition | Paste the `.asddls` into the data definition |
| "Cannot annotate ... type of the annotated entity is not supported" | Metadata extensions are not supported on custom entities in this system | UI annotations directly in the custom entity; no metadata extension |
| "Unexpected character" in the data definition | Text after the closing `}` or an ABAP-style comment (`*`, `"`) | CDS comments are `//` or `/* */`; nothing after `}` |

## Known limits

- Blocking engine errors (wrong period range, company code not in controlling area 2000, no customizing, inconsistent customizing) are shown as an error message. Warnings (a SET that could not be expanded, a formula skipped, no process orders in the SET) appear in the Remark column of the affected lines.
- The authorization check uses `Y0000CO_FI_AUTHORITY_CHECKS` like the report. Its behaviour on a failed check inside an OData request is not verified yet (it may end the request with an error).
- The engine runs once per request; caches do not survive between requests.

## Next stages

Drill-down: cost center / order / cost element breakdown and formula components (level 2), then line items (level 3).
