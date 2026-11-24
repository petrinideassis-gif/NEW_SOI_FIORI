# NEW_SOI_FIORI

Fiori Elements preview of the Statement of Income (SOI) report (`Y0000CO_SOI_NEW` in `NEW_SOI-AND-PCBUCKE`), built as a RAP custom entity with a query provider class (S/4HANA 2023, OData V4).

Design: [docs/design-note.md](docs/design-note.md).

## Objects in this repository (stage 1, stub)

| Type | Object | File |
|---|---|---|
| Custom entity | `Y0000CO_C_SOILINE` | `cds/Y0000CO_C_SOILINE.asddls` |
| Query class | `Y0000CO_CL_SOI_QUERY` | `src/classes/Y0000CO_CL_SOI_QUERY.abap` |
| Metadata extension | `Y0000CO_C_SOILINE` | `metadata-extensions/Y0000CO_C_SOILINE.asddlxs` |
| Service definition | `Y0000CO_UI_SOI` | `service/Y0000CO_UI_SOI.srvd` |

The service binding `Y0000CO_UI_SOI_O4` is created in ADT, not stored here.

Stage 1 returns the real SOI lines and texts of the selected version with amount zero. It proves the plumbing before the engine is connected.

## Restore order in ADT (one object at a time, activate before the next)

1. Class `Y0000CO_CL_SOI_QUERY`: New ABAP Class, add interface `IF_RAP_QUERY_PROVIDER`, paste the source (replace the generated definition and implementation), save, activate
2. Custom entity `Y0000CO_C_SOILINE`: New Data Definition (template for custom entity; if none is offered, use the empty template), paste, save, activate
3. Metadata extension `Y0000CO_C_SOILINE` (same name), paste, activate
4. Service definition `Y0000CO_UI_SOI`, paste, activate
5. Service binding `Y0000CO_UI_SOI_O4`: type OData V4 - UI, on that service definition, activate, publish
6. Run `/IWFND/CACHE_CLEANUP` and `/IWBEP/CACHE_CLEANUP`, then open the preview from the binding (entity set `SOILine`)

Use package `$TMP` while testing; move to the real package with a transport once it works.

## Stage 1 checks in the preview

1. Filter bar shows version, year, company code, value type, version; the first three are marked mandatory
2. Defaults: version `STD`, value type `04`, version `000`
3. Go with year and company code: the SOI lines of version `STD` appear in outline order with their texts
4. Compare the lines and texts with the classic report `Y0000CO_SOI_NEW` for the same version
5. Amount column is zero in stage 1

## Next stages

Stage 2: engine copy `Y0000CO_CL_SOI_ENGINE`, authorization check first, real totals in total mode. Verify against `Y0000CO_SOI_NEW` in total mode, line by line.
