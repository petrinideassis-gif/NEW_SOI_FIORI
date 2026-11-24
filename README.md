# NEW_SOI_FIORI

Fiori Elements preview of the Statement of Income (SOI) report (`Y0000CO_SOI_NEW` in `NEW_SOI-AND-PCBUCKE`), built as a RAP custom entity with a query provider class (S/4HANA 2023, OData V4).

Design: [docs/design-note.md](docs/design-note.md).

## Objects in this repository (stage 1, stub)

| Type | Object | File |
|---|---|---|
| Custom entity | `Y0000CO_C_SOILINE` | `cds/Y0000CO_C_SOILINE.asddls` |
| Query class | `Y0000CO_CL_SOI_QUERY` | `src/classes/Y0000CO_CL_SOI_QUERY.abap` |
| Service definition | `Y0000CO_UI_SOI` | `service/Y0000CO_UI_SOI.srvd` |

The service binding `Y0000CO_UI_SOI_O4` is created in ADT, not stored here.

No metadata extension: this system does not allow one on a custom entity, so the UI annotations (`@UI.selectionField`, `@UI.lineItem`, `@UI.headerInfo`) are in the custom entity itself.

Stage 1 returns the real SOI lines and texts of the selected version with amount zero. It proves the plumbing before the engine is connected.

## Restore order in ADT (one object at a time, activate before the next)

1. Custom entity `Y0000CO_C_SOILINE`: New Data Definition (template for custom entity; if none is offered, any template), Ctrl+A, paste, save, activate. A warning that the class does not exist yet is expected
2. Class `Y0000CO_CL_SOI_QUERY`: New ABAP Class, add interface `IF_RAP_QUERY_PROVIDER`, Ctrl+A, paste, fill the header placeholders, save, activate. Then activate the entity once more
3. Service definition `Y0000CO_UI_SOI`, paste, activate
4. Service binding `Y0000CO_UI_SOI_O4`: type OData V4 - UI, on that service definition, activate, publish
5. Run `/IWFND/CACHE_CLEANUP` and `/IWBEP/CACHE_CLEANUP`, then open the preview from the binding (entity set `SOILine`)

All objects go into package `Y0000CO_ALL_OBJECTS`, on one transport request.

## Stage 1 checks in the preview

1. Filter bar shows version, year, company code, value type, version; the first three are marked mandatory
2. Defaults: version `STD`, value type `04`, version `000`
3. Go with year and company code: the SOI lines of version `STD` appear in outline order with their texts
4. Compare the lines and texts with the classic report `Y0000CO_SOI_NEW` for the same version
5. Amount column is zero in stage 1

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

## Next stages

Stage 2: engine copy `Y0000CO_CL_SOI_ENGINE`, authorization check first, real totals in total mode. Verify against `Y0000CO_SOI_NEW` in total mode, line by line.
