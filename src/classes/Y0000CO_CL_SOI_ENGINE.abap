*----------------------------------------------------------------------*
* Description : SOI engine for the Fiori preview
*----------------------------------------------------------------------*
* ABAP Name     : Y0000CO_CL_SOI_ENGINE
* Author        : <SAP user ID>
* Date          : 24.11.2026
* Reference No. : <CHG0000000 / CTASK0000000>
*----------------------------------------------------------------------*
*  Changes     (internal Version: Documentation/Info on line level)    *
*----------------------------------------------------------------------*
*  Date       Name    internal    Transp.No. Description               *
*                    -Version-    Refer. No.                           *
*                                                                      *
*----------------------------------------------------------------------*
*  Purpose
*  Computes the Statement of Income (SOI) lines for one company code,
*  fiscal year, version and value type over a period range (default
*  1-16), optionally compared against a second data set.
*  Used by the query provider Y0000CO_CL_SOI_QUERY of the SOI Fiori
*  preview.
*
*  The engine is a copy of the engine part of report Y0000CO_SOI_NEW
*  (READ_CUSTOMIZING, PREPARE_RULE_SCOPES, PREPARE_ORDER_SCOPE,
*  READ_ORDER_TOTALS, SELECT_TOTALS_FOR_RULE, BUILD_SUMMARY_DATA,
*  APPLY_FORMULA_LINES and their helpers). The report is NOT changed;
*  both must give the same totals for the same selection.
*
*  Typical business use:
*  Controllers open the SOI preview in Fiori instead of running the
*  classic report in SAP GUI.
*
*  Main Steps
*  1. Check authorization for the company code
*  2. Validate company code, read currency and SOI customizing
*  3. Expand Cost Center / Cost Element groups (once per run)
*  4. Expand the Process Order SET and read the order totals
*  5. Accumulate COSP/COSS totals per extraction rule
*  6. Resolve METHOD R formula lines in dependency order
*  7. Optionally repeat steps 4-6 for the comparison data set
*  8. Return one line per SOI line with periods, total and comparison
*
*  Important technical notes from development:
*  - Controlling area (KOKRS) is fixed to '2000'; ledger LEDNR '00'
*  - One period range for both data sets instead of the report's
*    display modes: blank = 1-16 (total mode), From/To = detail mode,
*    To alone = the comparison cap P_CMPTO
*  - Differences to Y0000CO_SOI_NEW: selection parameters P_BUKRS /
*    P_SOIVAR / P_GJAHR / P_VERSN / P_WRTTP come from the run context
*    (GV_BUKRS / GV_SOIVAR / GV_GJAHR / GV_VERSN / GV_WRTTP); dialog
*    messages are collected in GT_MESSAGES (GET_MESSAGES) instead of
*    being sent; no ALV
*  - Line items (GET_LINE_ITEMS) need only the checks of START_RUN,
*    not the full SOI run
*  - Drill-down (GET_DETAILS) reuses the state of the last RUN, as the
*    report's double-click reuses the state of the report run
*  - Error that stops the run (wrong period range, unknown company
*    code, company code not in KOKRS 2000, no customizing, inconsistent
*    customizing): RUN returns no lines and GET_ERROR says why
*  - Non-blocking warnings (SET not expanded, formula skipped, empty
*    process order SET) are attached to the affected lines as REMARK
*  - Caches live for one RUN only: the engine is created per request
*  - Comments must stay inside METHOD ... ENDMETHOD: the class editor
*    rejects comments between method implementations
*----------------------------------------------------------------------*
class y0000co_cl_soi_engine definition
  public
  final
  create public.

  public section.

*---------------------------------------------------------------------*
* Run context and result
*---------------------------------------------------------------------*
* TY_CONTEXT replaces the selection screen of Y0000CO_SOI_NEW.
* PERV / PERB bound the periods for BOTH data sets (1-16; the report's
* total mode is 1-16, its detail mode the entered range, its P_CMPTO
* cap is PERB). COMPARE requests a second data set (GJAHR2 / VERSN2 /
* WRTTP2, each falling back to its main field when blank).
* TY_LINE is one SOI line: periods 1-12, the special periods 13-16 as
* one value, the total over PERV-PERB and the comparison columns.
*---------------------------------------------------------------------*
    types:
      ty_pct type p length 9 decimals 2.

    types:
      begin of ty_context,
        soivar  type y0000co_nsoi00-soivar,
        bukrs   type bukrs,
        gjahr   type gjahr,
        versn   type versn,
        wrttp   type wrttp,
        perv    type i,
        perb    type i,
        compare type abap_bool,
        gjahr2  type gjahr,
        versn2  type versn,
        wrttp2  type wrttp,
      end of ty_context,

      begin of ty_line,
        soiline    type y0000co_nsoi01-soiline,
        outline    type y0000co_nsoi01-outline,
        text       type y0000co_nsoi01t-text,
        val001     type v_coss_view-wog001,
        val002     type v_coss_view-wog001,
        val003     type v_coss_view-wog001,
        val004     type v_coss_view-wog001,
        val005     type v_coss_view-wog001,
        val006     type v_coss_view-wog001,
        val007     type v_coss_view-wog001,
        val008     type v_coss_view-wog001,
        val009     type v_coss_view-wog001,
        val010     type v_coss_view-wog001,
        val011     type v_coss_view-wog001,
        val012     type v_coss_view-wog001,
        special    type v_coss_view-wog001,
        total      type v_coss_view-wog001,
        total_cmp  type v_coss_view-wog001,
        diff_abs   type v_coss_view-wog001,
        diff_pct   type ty_pct,
        waers      type waers,
        is_formula type abap_bool,
        remark     type string,
      end of ty_line,

      tt_line type standard table of ty_line with empty key.

*---------------------------------------------------------------------*
* Drill-down row (one per cost center/order and cost element, or one
* per formula component)
*---------------------------------------------------------------------*
* ROW_TYPE: 'C' cost center, 'O' process order, 'F' formula component.
* Same content as the report's drill-down grid (TY_DETAIL_DISP):
* VALUE is the row's total over the period range (pass A), VALUE_CMP
* pass B. Formula components are unsigned, as their own SOI line
* shows them; OPER_TYPE says how they combine.
*---------------------------------------------------------------------*
    types:
      begin of ty_detail,
        row_type     type c length 1,
        kostl        type kostl,
        kosar        type kosar,
        kosar_txt    type c length 50,
        fkber        type fkber,
        fkber_txt    type c length 50,
        aufnr        type aufnr,
        kstar        type kstar,
        kstar_txt    type c length 50,
        comp_soiline type y0000co_nsoi01-soiline,
        comp_text    type y0000co_nsoi01t-text,
        oper_type    type y0000co_nsoi03-oper_type,
        val001       type v_coss_view-wog001,
        val002       type v_coss_view-wog001,
        val003       type v_coss_view-wog001,
        val004       type v_coss_view-wog001,
        val005       type v_coss_view-wog001,
        val006       type v_coss_view-wog001,
        val007       type v_coss_view-wog001,
        val008       type v_coss_view-wog001,
        val009       type v_coss_view-wog001,
        val010       type v_coss_view-wog001,
        val011       type v_coss_view-wog001,
        val012       type v_coss_view-wog001,
        special      type v_coss_view-wog001,
        value        type v_coss_view-wog001,
        value_cmp    type v_coss_view-wog001,
        diff_abs     type v_coss_view-wog001,
        diff_pct     type ty_pct,
        waers        type waers,
      end of ty_detail,

      tt_detail type standard table of ty_detail with empty key.

*---------------------------------------------------------------------*
* Line item behind a breakdown row (as TY_LINE_ITEM in the report)
*---------------------------------------------------------------------*
* DATA_SET: 'A' base data set, 'B' comparison data set. COEP rows are
* postings; COEJ (plan) rows are exploded to one row per period.
*---------------------------------------------------------------------*
    types:
      begin of ty_line_item,
        data_set type c length 1,
        belnr    type coep-belnr,
        buzei    type coep-buzei,
        perio    type coep-perio,
        objnr    type coep-objnr,
        kostl    type kostl,
        kstar    type coep-kstar,
        gjahr    type coep-gjahr,
        versn    type coep-versn,
        wogbtr   type coep-wogbtr,
        waers    type waers,
        bldat    type cobk-bldat,
        budat    type cobk-budat,
        cpudt    type cobk-cpudt,
        usnam    type cobk-usnam,
        bltxt    type cobk-bltxt,
      end of ty_line_item,

      tt_line_item type standard table of ty_line_item with empty key.

    methods:
      run
        importing is_context    type ty_context
        returning value(rt_line) type tt_line,

      get_messages
        returning value(rt_messages) type string_table,

      get_error
        returning value(rv_error) type string,

      get_details
        importing iv_soiline       type y0000co_nsoi01-soiline
        returning value(rt_detail) type tt_detail,

      get_lines
        returning value(rt_line) type tt_line,

      get_line_items
        importing is_context    type ty_context
                  iv_kostl      type kostl
                  iv_kstar      type kstar
        returning value(rt_item) type tt_line_item.

  private section.

*---------------------------------------------------------------------*
* Fixed business constants (as in Y0000CO_SOI_NEW)
*---------------------------------------------------------------------*
* Controlling area is always 2000. LEDNR '00' is the standard CO
* ledger. GC_FALLBACK_LANGU is used when a SOI line has no text in the
* logon language. GC_PERIOD_MAX is the last period COSP/COSS carries
* (12 posting periods plus 4 special periods).
*---------------------------------------------------------------------*
    constants:
      gc_kokrs          type kokrs             value '2000',
      gc_lednr          type v_coss_view-lednr value '00',
      gc_fallback_langu type sy-langu          value 'E',
      gc_period_max     type i                 value 16,
      gc_pct_max        type p length 9 decimals 2 value '9999999.99'.

*---------------------------------------------------------------------*
* Period / SOI summary structures
*---------------------------------------------------------------------*
* TY_PERIOD_SUM holds one set of period 001-016 values (raw COSP/COSS
* WOGnnn columns renamed to VALnnn); TY_SUMMARY is one SOI line,
* extraction or formula. Comparison and colour fields of the report
* are left out.
*---------------------------------------------------------------------*
    types: ty_period type n length 3.

    types:
      begin of ty_period_sum,
        val001 type v_coss_view-wog001,
        val002 type v_coss_view-wog002,
        val003 type v_coss_view-wog003,
        val004 type v_coss_view-wog004,
        val005 type v_coss_view-wog005,
        val006 type v_coss_view-wog006,
        val007 type v_coss_view-wog007,
        val008 type v_coss_view-wog008,
        val009 type v_coss_view-wog009,
        val010 type v_coss_view-wog010,
        val011 type v_coss_view-wog011,
        val012 type v_coss_view-wog012,
        val013 type v_coss_view-wog013,
        val014 type v_coss_view-wog014,
        val015 type v_coss_view-wog015,
        val016 type v_coss_view-wog016,
      end of ty_period_sum,

      begin of ty_summary,
        soiline    type y0000co_nsoi01-soiline,
        outline    type y0000co_nsoi01-outline,
        text       type y0000co_nsoi01t-text,
        val001     type v_coss_view-wog001,
        val002     type v_coss_view-wog002,
        val003     type v_coss_view-wog003,
        val004     type v_coss_view-wog004,
        val005     type v_coss_view-wog005,
        val006     type v_coss_view-wog006,
        val007     type v_coss_view-wog007,
        val008     type v_coss_view-wog008,
        val009     type v_coss_view-wog009,
        val010     type v_coss_view-wog010,
        val011     type v_coss_view-wog011,
        val012     type v_coss_view-wog012,
        val013     type v_coss_view-wog013,
        val014     type v_coss_view-wog014,
        val015     type v_coss_view-wog015,
        val016     type v_coss_view-wog016,
        line_sum   type v_coss_view-wog001,
        waers      type waers,
        is_formula type abap_bool,
      end of ty_summary.

*---------------------------------------------------------------------*
* Customizing row structures (Y0000CO_NSOI01/01T/02/03)
*---------------------------------------------------------------------*
    types:
      begin of ty_soi01,
        soiline type y0000co_nsoi01-soiline,
        outline type y0000co_nsoi01-outline,
        text    type y0000co_nsoi01t-text,
      end of ty_soi01,

      begin of ty_rule,
        soiline type y0000co_nsoi02-soiline,
        method  type y0000co_nsoi02-method,
        kokrs   type y0000co_nsoi02-kokrs,
        ksgru   type y0000co_nsoi02-ksgru,
        kagru   type y0000co_nsoi02-kagru,
      end of ty_rule,

      begin of ty_formula,
        soiline      type y0000co_nsoi03-soiline,
        comp_soiline type y0000co_nsoi03-comp_soiline,
        oper_type    type y0000co_nsoi03-oper_type,
      end of ty_formula.

*---------------------------------------------------------------------*
* SET expansion / object scope helper structures
*---------------------------------------------------------------------*
* TY_SET_VALUE is one raw G_SET_TREE_IMPORT result line; TY_KOSTL_SCOPE
* and TY_OBJ_SCOPE hold expanded cost centers / CO object numbers.
*---------------------------------------------------------------------*
    types:
      begin of ty_set_value,
        from type setvalues-from,
        to   type setvalues-to,
      end of ty_set_value,

      begin of ty_kostl_scope,
        kostl type csks-kostl,
      end of ty_kostl_scope,

      begin of ty_obj_scope,
        objnr type j_objnr,
      end of ty_obj_scope.

    types:
      tt_summary     type standard table of ty_summary     with empty key,
      tt_soi01       type standard table of ty_soi01       with empty key,
      tt_rule        type standard table of ty_rule        with empty key,
      tt_formula     type standard table of ty_formula     with empty key,
      tt_set_value   type standard table of ty_set_value   with empty key,
      tt_kostl_scope type sorted table   of ty_kostl_scope with unique key kostl,
      tt_obj_scope   type sorted table   of ty_obj_scope   with unique key objnr,
      tt_r_objnr     type range of j_objnr,
      tt_r_kstar     type range of kstar.

*---------------------------------------------------------------------*
* Cost center object number cache (METHOD C)
*---------------------------------------------------------------------*
    types: begin of ty_cc_cache,
             kokrs type kokrs,
             bukrs type bukrs,
             ksgru type y0000co_nsoi02-ksgru,
             objnr type j_objnr,
           end of ty_cc_cache.

    types tt_cc_cache type sorted table of ty_cc_cache
      with unique key kokrs bukrs ksgru objnr.

*---------------------------------------------------------------------*
* Cost element (KSTAR) range cache
*---------------------------------------------------------------------*
    types: begin of ty_kstar_cache,
             kokrs  type kokrs,
             kagru  type y0000co_nsoi02-kagru,
             sign   type c length 1,
             option type c length 2,
             low    type kstar,
             high   type kstar,
           end of ty_kstar_cache.

    types tt_kstar_cache type sorted table of ty_kstar_cache
      with non-unique key kokrs kagru.

*---------------------------------------------------------------------*
* Process order object number cache (METHOD A)
*---------------------------------------------------------------------*
    types: begin of ty_order_cache,
             bukrs type bukrs,
             gjahr type gjahr,
             objnr type j_objnr,
           end of ty_order_cache.

    types tt_order_cache type sorted table of ty_order_cache
      with unique key bukrs gjahr objnr.

*---------------------------------------------------------------------*
* Process order period totals (METHOD A)
*---------------------------------------------------------------------*
* Order numbers don't encode KOKRS/BUKRS, so they are matched via one
* EQ per order in the OBJNR range, read once per run regardless of how
* many KAGRU groups use METHOD A (see READ_ORDER_TOTALS).
*---------------------------------------------------------------------*
    types: begin of ty_order_total_row,
             objnr  type j_objnr,
             kstar  type kstar,
             wog001 type v_coss_view-wog001,
             wog002 type v_coss_view-wog002,
             wog003 type v_coss_view-wog003,
             wog004 type v_coss_view-wog004,
             wog005 type v_coss_view-wog005,
             wog006 type v_coss_view-wog006,
             wog007 type v_coss_view-wog007,
             wog008 type v_coss_view-wog008,
             wog009 type v_coss_view-wog009,
             wog010 type v_coss_view-wog010,
             wog011 type v_coss_view-wog011,
             wog012 type v_coss_view-wog012,
             wog013 type v_coss_view-wog013,
             wog014 type v_coss_view-wog014,
             wog015 type v_coss_view-wog015,
             wog016 type v_coss_view-wog016,
           end of ty_order_total_row.

    types tt_order_total_row type standard table of ty_order_total_row with empty key.

*---------------------------------------------------------------------*
* Per-rule result cache
*---------------------------------------------------------------------*
* Identical rules reused by several SOI lines hit the database once.
*---------------------------------------------------------------------*
    types: begin of ty_totals_cache,
             method  type y0000co_nsoi02-method,
             kokrs   type kokrs,
             bukrs   type bukrs,
             ksgru   type y0000co_nsoi02-ksgru,
             kagru   type y0000co_nsoi02-kagru,
             periods type ty_period_sum,
           end of ty_totals_cache.

    types tt_totals_cache type sorted table of ty_totals_cache
      with unique key method kokrs bukrs ksgru kagru.

*---------------------------------------------------------------------*
* Drill-down build table (as TY_DETAIL_OBJECT in the report)
*---------------------------------------------------------------------*
* Sorted by cost center, order and cost element, so MERGE_DETAIL_OBJECT
* can upsert. KOSTL and AUFNR are mutually exclusive per row.
*---------------------------------------------------------------------*
    types:
      begin of ty_detail_object,
        kostl     type kostl,
        aufnr     type aufnr,
        kstar     type kstar,
        val001    type v_coss_view-wog001,
        val002    type v_coss_view-wog001,
        val003    type v_coss_view-wog001,
        val004    type v_coss_view-wog001,
        val005    type v_coss_view-wog001,
        val006    type v_coss_view-wog001,
        val007    type v_coss_view-wog001,
        val008    type v_coss_view-wog001,
        val009    type v_coss_view-wog001,
        val010    type v_coss_view-wog001,
        val011    type v_coss_view-wog001,
        val012    type v_coss_view-wog001,
        val013    type v_coss_view-wog001,
        val014    type v_coss_view-wog001,
        val015    type v_coss_view-wog001,
        val016    type v_coss_view-wog001,
        value     type v_coss_view-wog001,
        value_cmp type v_coss_view-wog001,
      end of ty_detail_object,
      tt_detail_object type sorted table of ty_detail_object
        with unique key kostl aufnr kstar.

*---------------------------------------------------------------------*
* Warnings per object, for the remark column
*---------------------------------------------------------------------*
* A SET group that could not be expanded (KIND 'C' cost center group,
* 'K' cost element group), so every SOI line using it gets a remark.
*---------------------------------------------------------------------*
    types: begin of ty_failed_group,
             kind  type c length 1,
             kokrs type kokrs,
             group type y0000co_nsoi02-ksgru,
           end of ty_failed_group.

    types tt_failed_group type sorted table of ty_failed_group
      with unique key kind kokrs group.

*---------------------------------------------------------------------*
* Instance state (one run)
*---------------------------------------------------------------------*
* GV_BUKRS / GV_SOIVAR replace P_BUKRS / P_SOIVAR of the report.
* GV_PERV / GV_PERB are the period bounds of the run. GV_ERROR stops
* the run after a blocking customizing or master data error.
*---------------------------------------------------------------------*
    data:
      gv_bukrs        type bukrs,
      gv_soivar       type y0000co_nsoi00-soivar,
      gv_waers        type waers,
      gv_gjahr        type v_coss_view-gjahr,
      gv_versn        type v_coss_view-versn,
      gv_wrttp        type v_coss_view-wrttp,
      gv_perv         type i,
      gv_perb         type i,
      gv_error        type abap_bool,
      gv_error_text   type string,
      gt_messages     type string_table,
      gt_failed_group type tt_failed_group,
      gt_order_sets_missing type string_table,
      gt_formula_skipped type sorted table of y0000co_nsoi01-soiline with unique key table_line,
      gv_compare      type abap_bool,
      gv_gjahr_a      type v_coss_view-gjahr,
      gv_versn_a      type v_coss_view-versn,
      gv_wrttp_a      type v_coss_view-wrttp,
      gt_summary_a    type tt_summary,
      gt_order_totals_a type tt_order_total_row,
      gt_lines        type tt_line,
      gt_soi01        type tt_soi01,
      gt_rule         type tt_rule,
      gt_formula      type tt_formula,
      gt_summary      type tt_summary,
      gt_cc_cache     type tt_cc_cache,
      gt_kstar_cache  type tt_kstar_cache,
      gt_order_cache  type tt_order_cache,
      gt_order_totals type tt_order_total_row,
      gt_totals_cache type tt_totals_cache.

*---------------------------------------------------------------------*
* Methods (names as in Y0000CO_SOI_NEW)
*---------------------------------------------------------------------*
    methods:
      check_authority,

      add_message
        importing iv_text  type string
                  iv_error type abap_bool default abap_false,

      validate_company_code,

      read_currency,

      read_customizing,

      validate_customizing,

      get_set_values
        importing iv_setid  type sethier-setid
        changing  ct_values type tt_set_value
                  cv_found  type abap_bool,

      resolve_cc_by_group_bukrs
        importing iv_kokrs      type kokrs
                  iv_ksgru      type y0000co_nsoi02-ksgru
        changing  ct_costcenter type tt_kostl_scope
                  cv_found      type abap_bool,

      build_objnr_from_costcenters
        importing it_costcenter type tt_kostl_scope
        changing  ct_objnr      type tt_obj_scope,

      resolve_kstar_group
        importing iv_kokrs type kokrs
                  iv_kagru type y0000co_nsoi02-kagru
        changing  ct_kstar type tt_r_kstar
                  cv_found type abap_bool,

      prepare_order_scope,

      read_order_totals,

      read_order_totals_batch
        importing it_r_objnr type tt_r_objnr
                  it_r_kstar type tt_r_kstar,

      periods_from_wog
        importing iv_source  type any
        changing  cs_periods type ty_period_sum,

      accumulate_periods
        importing is_add   type ty_period_sum
        changing  cs_total type ty_period_sum,

      add_periods_to_summary
        importing is_periods type ty_period_sum
        changing  cs_summary type ty_summary,

      select_totals_for_rule
        importing is_rule    type ty_rule
                  iv_bukrs   type bukrs
                  it_objnr   type tt_obj_scope
                  it_kstar   type tt_r_kstar
        changing  cs_summary type ty_summary,

      prepare_rule_scopes,

      get_cached_objnr
        importing iv_kokrs type kokrs
                  iv_bukrs type bukrs
                  iv_ksgru type y0000co_nsoi02-ksgru
        changing  ct_objnr type tt_obj_scope,

      get_cached_order_objnr
        changing ct_objnr type tt_obj_scope,

      get_cached_kstar
        importing iv_kokrs type kokrs
                  iv_kagru type y0000co_nsoi02-kagru
        changing  ct_kstar type tt_r_kstar,

      build_summary_data,

      apply_formula_lines,

      run_pass,

      build_remark
        importing iv_soiline      type y0000co_nsoi01-soiline
        returning value(rv_remark) type string,

      collect_order_detail
        importing it_order_totals type tt_order_total_row
                  it_kstar        type tt_r_kstar
                  iv_pass         type char1
        changing  ct_detail       type tt_detail_object,

      collect_cc_detail
        importing iv_gjahr  type v_coss_view-gjahr
                  iv_versn  type v_coss_view-versn
                  iv_wrttp  type v_coss_view-wrttp
                  it_objnr  type tt_obj_scope
                  it_kstar  type tt_r_kstar
                  iv_pass   type char1
        changing  ct_detail type tt_detail_object,

      merge_detail_object
        importing iv_kostl   type kostl
                  iv_aufnr   type aufnr
                  iv_kstar   type kstar
                  is_periods type ty_period_sum
                  iv_pass    type char1
        changing  ct_detail  type tt_detail_object,

      decode_objnr
        importing iv_objnr type j_objnr
        exporting ev_kostl type kostl
                  ev_aufnr type aufnr,

      sum_periods_in_range
        importing is_periods    type ty_period_sum
        returning value(rv_sum) type v_coss_view-wog001,

      enrich_detail_texts
        changing ct_detail type tt_detail,

      start_run
        importing is_context type ty_context,

      read_line_items
        importing iv_data_set type char1
                  it_objnr    type tt_r_objnr
                  iv_gjahr    type gjahr
                  iv_versn    type versn
                  iv_wrttp    type wrttp
                  iv_kstar    type kstar
        changing  ct_items    type tt_line_item,

      diff_percent
        importing iv_base       type v_coss_view-wog001
                  iv_diff       type v_coss_view-wog001
        returning value(rv_pct) type ty_pct.

endclass.


class y0000co_cl_soi_engine implementation.

  method run.
*---------------------------------------------------------------------*
* Run the SOI engine for one context
*---------------------------------------------------------------------*
* Same sequence as RUN of Y0000CO_SOI_NEW: authorization first, then
* customizing, the SET expansions (once, they do not depend on year,
* version or value type), pass A and - when requested - pass B with
* only the value caches reset. Any blocking error stops the run with
* no lines; GET_MESSAGES says why.
*---------------------------------------------------------------------*

    data: lv_period type ty_period.

    field-symbols: <lv_src> type any,
                   <lv_tgt> type any.

    start_run( is_context ).
    if gv_error = abap_true.
      return.
    endif.

    read_customizing( ).
    if gv_error = abap_true.
      return.
    endif.

    validate_customizing( ).
    if gv_error = abap_true.
      return.
    endif.

    prepare_rule_scopes( ).

*---------------------------------------------------------------------*
* Pass A - the base data set
*---------------------------------------------------------------------*
    gv_gjahr = is_context-gjahr.
    gv_versn = is_context-versn.
    gv_wrttp = is_context-wrttp.
    run_pass( ).

*   Pass A is kept for the drill-down (GET_DETAILS), as the report
*   snapshots it unconditionally in RUN.
    gv_gjahr_a        = gv_gjahr.
    gv_versn_a        = gv_versn.
    gv_wrttp_a        = gv_wrttp.
    gt_summary_a      = gt_summary.
    gt_order_totals_a = gt_order_totals.

*---------------------------------------------------------------------*
* Pass B - the comparison data set
*---------------------------------------------------------------------*
* Only the value caches are reset, as RESET_VALUE_CACHES in the report.
* After this block GT_SUMMARY holds pass B.
*---------------------------------------------------------------------*
    if is_context-compare = abap_true.
      clear: gt_order_cache, gt_order_totals, gt_totals_cache, gt_summary.

      gv_gjahr = cond #( when is_context-gjahr2 is initial then is_context-gjahr else is_context-gjahr2 ).
      gv_versn = cond #( when is_context-versn2 is initial then is_context-versn else is_context-versn2 ).
      gv_wrttp = cond #( when is_context-wrttp2 is initial then is_context-wrttp else is_context-wrttp2 ).
      run_pass( ).
    endif.

*---------------------------------------------------------------------*
* Result lines
*---------------------------------------------------------------------*
* Periods outside PERV-PERB stay zero, so the period columns plus the
* special periods add up to the total. Comparison columns follow
* BUILD_COMPARISON of the report: B - A, and the percentage over
* ABS(A) (see DIFF_PERCENT).
*---------------------------------------------------------------------*
    loop at gt_summary_a into data(ls_summary).
      data(ls_line) = value ty_line(
        soiline    = ls_summary-soiline
        outline    = ls_summary-outline
        text       = ls_summary-text
        special    = ls_summary-val013 + ls_summary-val014
                   + ls_summary-val015 + ls_summary-val016
        total      = ls_summary-line_sum
        waers      = ls_summary-waers
        is_formula = ls_summary-is_formula
        remark     = build_remark( ls_summary-soiline ) ).

      do 12 times.
        lv_period = sy-index.
        assign component |VAL{ lv_period }| of structure ls_summary to <lv_src>.
        assign component |VAL{ lv_period }| of structure ls_line to <lv_tgt>.
        if <lv_src> is assigned and <lv_tgt> is assigned.
          <lv_tgt> = <lv_src>.
        endif.
        unassign: <lv_src>, <lv_tgt>.
      enddo.

      if is_context-compare = abap_true.
        read table gt_summary into data(ls_cmp)
          with key soiline = ls_summary-soiline.
        if sy-subrc = 0.
          ls_line-total_cmp = ls_cmp-line_sum.
        endif.

        ls_line-diff_abs = ls_line-total_cmp - ls_line-total.
        ls_line-diff_pct = diff_percent( iv_base = ls_line-total
                                         iv_diff = ls_line-diff_abs ).
      endif.

      append ls_line to rt_line.
    endloop.

    gt_lines = rt_line.

  endmethod.

  method start_run.
*---------------------------------------------------------------------*
* Common start of RUN and GET_LINE_ITEMS
*---------------------------------------------------------------------*
* Authorization first (convention), then the period bounds, company
* code and currency checks. Blank bounds mean the full year including
* the special periods, as the report's total mode; the same bounds
* apply to the comparison pass, which is what P_CMPTO does in the
* report. A blocking error sets GV_ERROR.
*---------------------------------------------------------------------*

    gv_bukrs  = is_context-bukrs.
    gv_soivar = is_context-soivar.

    check_authority( ).

    clear: gv_error, gv_error_text, gt_messages, gt_failed_group,
           gt_order_sets_missing, gt_formula_skipped,
           gt_summary_a, gt_order_totals_a, gt_lines,
           gt_soi01, gt_rule, gt_formula,
           gt_summary, gt_cc_cache, gt_kstar_cache, gt_order_cache,
           gt_order_totals, gt_totals_cache.

    gv_compare = is_context-compare.

    gv_perv = cond #( when is_context-perv is initial then 1 else is_context-perv ).
    gv_perb = cond #( when is_context-perb is initial then gc_period_max else is_context-perb ).

    if gv_perv < 1 or gv_perb > gc_period_max or gv_perv > gv_perb.
      add_message( iv_text  = |Periods must be between 1 and { gc_period_max }, and From <= To|
                   iv_error = abap_true ).
      return.
    endif.

    validate_company_code( ).
    if gv_error = abap_true.
      return.
    endif.

    read_currency( ).
  endmethod.


  method get_line_items.
*---------------------------------------------------------------------*
* Line items behind one breakdown row (cost center + cost element)
*---------------------------------------------------------------------*
* As SHOW_LINE_ITEMS in the report, without the full SOI run: only the
* checks of START_RUN are needed. The object scope matches the KS
* object exactly and the KL objects by pattern, the same pairing as
* SELECT_TOTALS_FOR_RULE, so the items add up to the breakdown row.
* Actuals (WRTTP 04) come from COEP, everything else from COEJ. The
* report showed one data set per double-click (the clicked column);
* here the base data set ('A') and, when comparing, the comparison
* data set ('B') are returned together.
*---------------------------------------------------------------------*
    data lt_objnr type tt_r_objnr.

    start_run( is_context ).
    if gv_error = abap_true or iv_kostl is initial or iv_kstar is initial.
      return.
    endif.

    lt_objnr = value #(
      ( sign = 'I' option = 'EQ' low = |KS{ gc_kokrs }{ iv_kostl }| )
      ( sign = 'I' option = 'CP' low = |KL{ gc_kokrs }{ iv_kostl }*| ) ).

    read_line_items(
      exporting iv_data_set = 'A'
                it_objnr    = lt_objnr
                iv_gjahr    = is_context-gjahr
                iv_versn    = is_context-versn
                iv_wrttp    = is_context-wrttp
                iv_kstar    = iv_kstar
      changing  ct_items    = rt_item ).

    if gv_compare = abap_true.
      read_line_items(
        exporting iv_data_set = 'B'
                  it_objnr    = lt_objnr
                  iv_gjahr    = cond #( when is_context-gjahr2 is initial then is_context-gjahr else is_context-gjahr2 )
                  iv_versn    = cond #( when is_context-versn2 is initial then is_context-versn else is_context-versn2 )
                  iv_wrttp    = cond #( when is_context-wrttp2 is initial then is_context-wrttp else is_context-wrttp2 )
                  iv_kstar    = iv_kstar
        changing  ct_items    = rt_item ).
    endif.
  endmethod.


  method read_line_items.
*---------------------------------------------------------------------*
* Read the line items of one data set (COEP actuals / COEJ plan)
*---------------------------------------------------------------------*
* COEP: one row per posting, value in WOGBTR, period in PERIO.
* COEJ: one row per fiscal year with WOG001-WOG016 across it; each row
* is exploded into one row per period in the range, zero periods are
* skipped (as READ_LINE_ITEMS_COEJ in the report).
* LEFT OUTER JOIN on the document header COBK: a line item must not
* vanish just because its header is missing.
*---------------------------------------------------------------------*
    data: ls_periods type ty_period_sum,
          ls_item    type ty_line_item,
          lv_period  type ty_period,
          lv_from    type coep-perio,
          lv_to      type coep-perio.

    field-symbols <lv_val> type any.

    lv_from = gv_perv.
    lv_to   = gv_perb.

    if iv_wrttp = '04'.
      select coep~belnr, coep~buzei, coep~objnr,
             coep~kstar, coep~versn, coep~gjahr, coep~perio,
             coep~wogbtr,
             cobk~bldat, cobk~budat, cobk~cpudt, cobk~usnam, cobk~bltxt
        from coep
        left outer join cobk
          on  cobk~kokrs = coep~kokrs
          and cobk~belnr = coep~belnr
        where coep~kokrs =  @gc_kokrs
          and coep~objnr in @it_objnr
          and coep~gjahr =  @iv_gjahr
          and coep~versn =  @iv_versn
          and coep~wrttp =  @iv_wrttp
          and coep~kstar =  @iv_kstar
          and coep~perio between @lv_from and @lv_to
        into table @data(lt_coep).

      loop at lt_coep into data(ls_coep).
        ls_item = corresponding #( ls_coep ).
        ls_item-data_set = iv_data_set.
        ls_item-waers    = gv_waers.
        decode_objnr(
          exporting iv_objnr = ls_coep-objnr
          importing ev_kostl = ls_item-kostl ).
        append ls_item to ct_items.
      endloop.

      return.
    endif.

    select coej~belnr, coej~buzei, coej~objnr,
           coej~kstar, coej~versn, coej~gjahr,
           coej~wog001, coej~wog002, coej~wog003, coej~wog004,
           coej~wog005, coej~wog006, coej~wog007, coej~wog008,
           coej~wog009, coej~wog010, coej~wog011, coej~wog012,
           coej~wog013, coej~wog014, coej~wog015, coej~wog016,
           cobk~bldat, cobk~budat, cobk~cpudt, cobk~usnam, cobk~bltxt
      from coej
      left outer join cobk
        on  cobk~kokrs = coej~kokrs
        and cobk~belnr = coej~belnr
      where coej~kokrs =  @gc_kokrs
        and coej~objnr in @it_objnr
        and coej~gjahr =  @iv_gjahr
        and coej~versn =  @iv_versn
        and coej~wrttp =  @iv_wrttp
        and coej~kstar =  @iv_kstar
      into table @data(lt_coej).

    loop at lt_coej into data(ls_coej).
      periods_from_wog( exporting iv_source  = ls_coej
                        changing  cs_periods = ls_periods ).

      clear ls_item.
      ls_item = corresponding #( ls_coej ).
      ls_item-data_set = iv_data_set.
      ls_item-waers    = gv_waers.

      decode_objnr(
        exporting iv_objnr = ls_coej-objnr
        importing ev_kostl = ls_item-kostl ).

      do gv_perb times.
        if sy-index < gv_perv.
          continue.
        endif.

        lv_period = sy-index.

        assign component |VAL{ lv_period }| of structure ls_periods to <lv_val>.
        if sy-subrc <> 0 or <lv_val> = 0.
          continue.
        endif.

        ls_item-perio  = lv_period.
        ls_item-wogbtr = <lv_val>.
        append ls_item to ct_items.
      enddo.
    endloop.
  endmethod.


  method run_pass.
*---------------------------------------------------------------------*
* One data set (GV_GJAHR / GV_VERSN / GV_WRTTP), as RUN_PASS in the
* report
*---------------------------------------------------------------------*
    prepare_order_scope( ).
    read_order_totals( ).

    build_summary_data( ).
    apply_formula_lines( ).
  endmethod.


  method diff_percent.
*---------------------------------------------------------------------*
* The comparison percentage (as DIFF_PERCENT in the report)
*---------------------------------------------------------------------*
* - divide by ABS(base), not the signed base: on an income statement
*   the base is negative on revenue lines, and the signed divisor would
*   flip the percentage so it contradicted the absolute difference
* - a zero base has no defined percentage; it stays zero
* - clamp, so a near-zero base cannot overflow the output field. The
*   intermediate is deliberately wider than the result.
*---------------------------------------------------------------------*
    data lv_pct type p length 15 decimals 2.

    rv_pct = 0.

    if iv_base = 0.
      return.
    endif.

    lv_pct = iv_diff / abs( iv_base ) * 100.

    if lv_pct > gc_pct_max.
      lv_pct = gc_pct_max.
    elseif lv_pct < gc_pct_max * -1.
      lv_pct = gc_pct_max * -1.
    endif.

    rv_pct = lv_pct.
  endmethod.


  method get_messages.
*---------------------------------------------------------------------*
* Messages collected during the last run
*---------------------------------------------------------------------*
    rt_messages = gt_messages.
  endmethod.


  method get_lines.
*---------------------------------------------------------------------*
* Result lines of the last run (same as RUN returned)
*---------------------------------------------------------------------*
    rt_line = gt_lines.
  endmethod.


  method get_error.
*---------------------------------------------------------------------*
* First blocking error of the last run (initial if the run completed)
*---------------------------------------------------------------------*
    rv_error = gv_error_text.
  endmethod.

  method get_details.
*---------------------------------------------------------------------*
* Drill-down for one SOI line (call after RUN)
*---------------------------------------------------------------------*
* Same logic as BUILD_DETAIL_FOR_ROW / BUILD_DETAIL_OBJECT /
* BUILD_DETAIL_FORMULA in the report:
* - formula line: one row per Y0000CO_NSOI03 component, from memory
* - extraction line: METHOD A rows from the order totals already read
*   (no new query), METHOD C rows from one small SELECT per rule scoped
*   to the rule's cached OBJNR/KSTAR ranges. Pass B only when comparing.
* Each row's VALUE is its total over the period range, so the rows add
* up to the SOI line's total.
*---------------------------------------------------------------------*
    data: lt_kstar  type tt_r_kstar,
          lt_objnr  type tt_obj_scope,
          lt_object type tt_detail_object,
          lv_period type ty_period.

    field-symbols: <lv_src> type any,
                   <lv_tgt> type any.

    read table gt_summary_a into data(ls_line) with key soiline = iv_soiline.
    if sy-subrc <> 0.
      return.
    endif.

*---------------------------------------------------------------------*
* Formula line: components
*---------------------------------------------------------------------*
* GT_SUMMARY_A holds pass A, GT_SUMMARY pass B (when comparing); every
* component already has its final total because APPLY_FORMULA_LINES
* resolved all formulas in dependency order.
*---------------------------------------------------------------------*
    if ls_line-is_formula = abap_true.
      loop at gt_formula into data(ls_formula) where soiline = iv_soiline.
        data(ls_row) = value ty_detail( row_type     = 'F'
                                        comp_soiline = ls_formula-comp_soiline
                                        oper_type    = ls_formula-oper_type
                                        waers        = gv_waers ).

        read table gt_summary_a into data(ls_comp) with key soiline = ls_formula-comp_soiline.
        if sy-subrc = 0.
          ls_row-comp_text = ls_comp-text.
          ls_row-value     = ls_comp-line_sum.
          ls_row-special   = ls_comp-val013 + ls_comp-val014 + ls_comp-val015 + ls_comp-val016.
          do 12 times.
            lv_period = sy-index.
            assign component |VAL{ lv_period }| of structure ls_comp to <lv_src>.
            assign component |VAL{ lv_period }| of structure ls_row to <lv_tgt>.
            if <lv_src> is assigned and <lv_tgt> is assigned.
              <lv_tgt> = <lv_src>.
            endif.
            unassign: <lv_src>, <lv_tgt>.
          enddo.
        endif.

        if gv_compare = abap_true.
          read table gt_summary into data(ls_comp_b) with key soiline = ls_formula-comp_soiline.
          if sy-subrc = 0.
            ls_row-value_cmp = ls_comp_b-line_sum.
          endif.
        endif.

        append ls_row to rt_detail.
      endloop.

    else.
*---------------------------------------------------------------------*
* Extraction line: cost center / order / cost element rows
*---------------------------------------------------------------------*
      loop at gt_rule into data(ls_rule) where soiline = iv_soiline and method <> 'R'.
        clear lt_kstar.
        get_cached_kstar(
          exporting iv_kokrs = ls_rule-kokrs
                    iv_kagru = ls_rule-kagru
          changing  ct_kstar = lt_kstar ).

        if ls_rule-method = 'A'.
          collect_order_detail(
            exporting it_order_totals = gt_order_totals_a
                      it_kstar        = lt_kstar
                      iv_pass         = 'A'
            changing  ct_detail       = lt_object ).

          if gv_compare = abap_true.
            collect_order_detail(
              exporting it_order_totals = gt_order_totals
                        it_kstar        = lt_kstar
                        iv_pass         = 'B'
              changing  ct_detail       = lt_object ).
          endif.

        else.
          clear lt_objnr.
          get_cached_objnr(
            exporting iv_kokrs = ls_rule-kokrs
                      iv_bukrs = gv_bukrs
                      iv_ksgru = ls_rule-ksgru
            changing  ct_objnr = lt_objnr ).

          collect_cc_detail(
            exporting iv_gjahr  = gv_gjahr_a
                      iv_versn  = gv_versn_a
                      iv_wrttp  = gv_wrttp_a
                      it_objnr  = lt_objnr
                      it_kstar  = lt_kstar
                      iv_pass   = 'A'
            changing  ct_detail = lt_object ).

          if gv_compare = abap_true.
            collect_cc_detail(
              exporting iv_gjahr  = gv_gjahr
                        iv_versn  = gv_versn
                        iv_wrttp  = gv_wrttp
                        it_objnr  = lt_objnr
                        it_kstar  = lt_kstar
                        iv_pass   = 'B'
              changing  ct_detail = lt_object ).
          endif.
        endif.
      endloop.

      loop at lt_object into data(ls_object).
        data(ls_obj_row) = value ty_detail(
          row_type  = cond #( when ls_object-aufnr is not initial then 'O' else 'C' )
          kostl     = ls_object-kostl
          aufnr     = ls_object-aufnr
          kstar     = ls_object-kstar
          special   = ls_object-val013 + ls_object-val014 + ls_object-val015 + ls_object-val016
          value     = ls_object-value
          value_cmp = ls_object-value_cmp
          waers     = gv_waers ).
        do 12 times.
          lv_period = sy-index.
          assign component |VAL{ lv_period }| of structure ls_object to <lv_src>.
          assign component |VAL{ lv_period }| of structure ls_obj_row to <lv_tgt>.
          if <lv_src> is assigned and <lv_tgt> is assigned.
            <lv_tgt> = <lv_src>.
          endif.
          unassign: <lv_src>, <lv_tgt>.
        enddo.
        append ls_obj_row to rt_detail.
      endloop.

      enrich_detail_texts( changing ct_detail = rt_detail ).
    endif.

*---------------------------------------------------------------------*
* Comparison columns (as COMPUTE_DETAIL_DIFFS in the report)
*---------------------------------------------------------------------*
    if gv_compare = abap_true.
      loop at rt_detail assigning field-symbol(<ls_detail>).
        <ls_detail>-diff_abs = <ls_detail>-value_cmp - <ls_detail>-value.
        <ls_detail>-diff_pct = diff_percent( iv_base = <ls_detail>-value
                                             iv_diff = <ls_detail>-diff_abs ).
      endloop.
    endif.
  endmethod.


  method collect_order_detail.
*---------------------------------------------------------------------*
* METHOD A object/cost-element rows - already in memory
*---------------------------------------------------------------------*
    data: ls_periods type ty_period_sum,
          lv_kostl   type kostl,
          lv_aufnr   type aufnr.

    loop at it_order_totals into data(ls_row) where kstar in it_kstar.
      decode_objnr(
        exporting iv_objnr = ls_row-objnr
        importing ev_kostl = lv_kostl
                  ev_aufnr = lv_aufnr ).

      periods_from_wog( exporting iv_source = ls_row changing cs_periods = ls_periods ).

      merge_detail_object(
        exporting iv_kostl   = lv_kostl
                  iv_aufnr   = lv_aufnr
                  iv_kstar   = ls_row-kstar
                  is_periods = ls_periods
                  iv_pass    = iv_pass
        changing  ct_detail  = ct_detail ).
    endloop.
  endmethod.


  method collect_cc_detail.
*---------------------------------------------------------------------*
* METHOD C object/cost-element rows - one small scoped query
*---------------------------------------------------------------------*
* Same query shape as SELECT_TOTALS_FOR_RULE, scoped to this one rule's
* cached OBJNR/KSTAR ranges, but keeping OBJNR/KSTAR instead of
* collapsing straight into a total.
*---------------------------------------------------------------------*
    data: lt_r_objnr type tt_r_objnr,
          ls_periods type ty_period_sum,
          lv_kostl   type kostl,
          lv_aufnr   type aufnr.

    field-symbols <ls_objnr_range> like line of lt_r_objnr.

    if it_objnr is initial or it_kstar is initial.
      return.
    endif.

    loop at it_objnr into data(ls_objnr).
      append initial line to lt_r_objnr assigning <ls_objnr_range>.

      <ls_objnr_range>-sign = 'I'.

      case ls_objnr-objnr(2).
        when 'KL'.
          <ls_objnr_range>-option = 'CP'.
        when others.
          <ls_objnr_range>-option = 'EQ'.
      endcase.

      <ls_objnr_range>-low = ls_objnr-objnr.
    endloop.

    if lt_r_objnr is initial.
      return.
    endif.

    select objnr, kstar,
           wog001, wog002, wog003, wog004,
           wog005, wog006, wog007, wog008,
           wog009, wog010, wog011, wog012,
           wog013, wog014, wog015, wog016
      from v_coss_view
      where lednr = @gc_lednr
        and gjahr = @iv_gjahr
        and wrttp = @iv_wrttp
        and versn = @iv_versn
        and kstar in @it_kstar
        and objnr in @lt_r_objnr
        and (
             wog001 <> 0 or wog002 <> 0 or
             wog003 <> 0 or wog004 <> 0 or
             wog005 <> 0 or wog006 <> 0 or
             wog007 <> 0 or wog008 <> 0 or
             wog009 <> 0 or wog010 <> 0 or
             wog011 <> 0 or wog012 <> 0 or
             wog013 <> 0 or wog014 <> 0 or
             wog015 <> 0 or wog016 <> 0
        )
      into table @data(lt_coss).

    loop at lt_coss into data(ls_coss).
      decode_objnr(
        exporting iv_objnr = ls_coss-objnr
        importing ev_kostl = lv_kostl
                  ev_aufnr = lv_aufnr ).
      periods_from_wog( exporting iv_source = ls_coss changing cs_periods = ls_periods ).
      merge_detail_object(
        exporting iv_kostl   = lv_kostl
                  iv_aufnr   = lv_aufnr
                  iv_kstar   = ls_coss-kstar
                  is_periods = ls_periods
                  iv_pass    = iv_pass
        changing  ct_detail  = ct_detail ).
    endloop.

    select objnr, kstar,
           wog001, wog002, wog003, wog004,
           wog005, wog006, wog007, wog008,
           wog009, wog010, wog011, wog012,
           wog013, wog014, wog015, wog016
      from v_cosp_view
      where lednr = @gc_lednr
        and gjahr = @iv_gjahr
        and wrttp = @iv_wrttp
        and versn = @iv_versn
        and kstar in @it_kstar
        and objnr in @lt_r_objnr
        and (
             wog001 <> 0 or wog002 <> 0 or
             wog003 <> 0 or wog004 <> 0 or
             wog005 <> 0 or wog006 <> 0 or
             wog007 <> 0 or wog008 <> 0 or
             wog009 <> 0 or wog010 <> 0 or
             wog011 <> 0 or wog012 <> 0 or
             wog013 <> 0 or wog014 <> 0 or
             wog015 <> 0 or wog016 <> 0
        )
      into table @data(lt_cosp).

    loop at lt_cosp into data(ls_cosp).
      decode_objnr(
        exporting iv_objnr = ls_cosp-objnr
        importing ev_kostl = lv_kostl
                  ev_aufnr = lv_aufnr ).
      periods_from_wog( exporting iv_source = ls_cosp changing cs_periods = ls_periods ).
      merge_detail_object(
        exporting iv_kostl   = lv_kostl
                  iv_aufnr   = lv_aufnr
                  iv_kstar   = ls_cosp-kstar
                  is_periods = ls_periods
                  iv_pass    = iv_pass
        changing  ct_detail  = ct_detail ).
    endloop.
  endmethod.


  method merge_detail_object.
*---------------------------------------------------------------------*
* Upsert one (cost center/order, cost element) row into the breakdown
*---------------------------------------------------------------------*
* Period columns are accumulated for pass A only. They are written
* component by component: <LS_DETAIL> points into a sorted table whose
* key fields are write-protected, so the whole row cannot be passed to
* a CHANGING parameter (see the report).
*---------------------------------------------------------------------*
    data lv_period type ty_period.

    field-symbols: <lv_add> type any,
                   <lv_tot> type any.

    read table ct_detail assigning field-symbol(<ls_detail>)
      with table key kostl = iv_kostl aufnr = iv_aufnr kstar = iv_kstar.

    if sy-subrc <> 0.
      insert value ty_detail_object(
        kostl = iv_kostl
        aufnr = iv_aufnr
        kstar = iv_kstar ) into table ct_detail
        assigning <ls_detail>.
    endif.

    if iv_pass <> 'A'.
      <ls_detail>-value_cmp = <ls_detail>-value_cmp + sum_periods_in_range( is_periods ).
      return.
    endif.

    <ls_detail>-value = <ls_detail>-value + sum_periods_in_range( is_periods ).

    do gv_perb times.
      if sy-index < gv_perv.
        continue.
      endif.

      lv_period = sy-index.

      assign component |VAL{ lv_period }| of structure is_periods to <lv_add>.
      if sy-subrc <> 0.
        continue.
      endif.

      assign component |VAL{ lv_period }| of structure <ls_detail> to <lv_tot>.
      if sy-subrc <> 0.
        continue.
      endif.

      <lv_tot> = <lv_tot> + <lv_add>.
    enddo.
  endmethod.


  method decode_objnr.
*---------------------------------------------------------------------*
* Decode a CO object number into a cost center or an order number
*---------------------------------------------------------------------*
* Mirrors, in reverse, how the OBJNR strings are built
* (BUILD_OBJNR_FROM_COSTCENTERS: 'KS'/'KL' + GC_KOKRS + KOSTL;
* PREPARE_ORDER_SCOPE: 'OR' + the SETLEAF order number).
*---------------------------------------------------------------------*
    data(lv_koffset) = 2 + strlen( gc_kokrs ).

    clear: ev_kostl, ev_aufnr.

    case iv_objnr(2).
      when 'KS' or 'KL'.
        ev_kostl = iv_objnr+lv_koffset.
      when 'OR'.
        ev_aufnr = iv_objnr+2.
    endcase.
  endmethod.


  method sum_periods_in_range.
*---------------------------------------------------------------------*
* Sum a period structure over the active period range
*---------------------------------------------------------------------*
    data lv_period type ty_period.

    field-symbols <lv_val> type any.

    rv_sum = 0.

    do gv_perb times.
      if sy-index < gv_perv.
        continue.
      endif.

      lv_period = sy-index.

      assign component |VAL{ lv_period }| of structure is_periods to <lv_val>.
      if sy-subrc = 0.
        rv_sum = rv_sum + <lv_val>.
      endif.
    enddo.
  endmethod.


  method enrich_detail_texts.
*---------------------------------------------------------------------*
* Add cost center and cost element master data to the breakdown
*---------------------------------------------------------------------*
* As ENRICH_DETAIL_TEXTS in the report: cost center category and
* functional area from CSKS (column FUNC_AREA), their texts from TKT05
* and TFKBT, the cost element text from CSKU (CSKA has no text). CSKS
* is time-dependent and not filtered on validity, so the most recent
* record per cost center wins (ORDER BY DATBI DESCENDING). Texts prefer
* the logon language and fall back to GC_FALLBACK_LANGU.
*---------------------------------------------------------------------*
    data: lr_kostl type range of kostl,
          lr_kstar type range of kstar,
          lv_ktopl type ktopl.

    loop at ct_detail into data(ls_scan).
      if ls_scan-kostl is not initial.
        append value #( sign = 'I' option = 'EQ' low = ls_scan-kostl ) to lr_kostl.
      endif.
      if ls_scan-kstar is not initial.
        append value #( sign = 'I' option = 'EQ' low = ls_scan-kstar ) to lr_kstar.
      endif.
    endloop.

    sort lr_kostl. delete adjacent duplicates from lr_kostl comparing all fields.
    sort lr_kstar. delete adjacent duplicates from lr_kstar comparing all fields.

    if lr_kostl is initial and lr_kstar is initial.
      return.
    endif.

    if lr_kostl is not initial.
      select kostl, kosar, func_area as fkber
        from csks
        where kokrs = @gc_kokrs
          and kostl in @lr_kostl
        order by kostl, datbi descending
        into table @data(lt_csks).
    endif.

    select kosar, ktext
      from tkt05
      into table @data(lt_kosar_txt).

    select fkber, spras, fkbtx
      from tfkbt
      where spras in ( @sy-langu, @gc_fallback_langu )
      into table @data(lt_fkber_txt).

    if lr_kstar is not initial.
      select single ktopl
        from tka01
        where kokrs = @gc_kokrs
        into @lv_ktopl.

      if sy-subrc = 0 and lv_ktopl is not initial.
        select kstar, spras, ktext
          from csku
          where ktopl = @lv_ktopl
            and kstar in @lr_kstar
            and spras in ( @sy-langu, @gc_fallback_langu )
          into table @data(lt_kstar_txt).
      endif.
    endif.

    loop at ct_detail assigning field-symbol(<ls_row>).
      if <ls_row>-kostl is not initial.
        read table lt_csks into data(ls_csks) with key kostl = <ls_row>-kostl.
        if sy-subrc = 0.
          <ls_row>-kosar = ls_csks-kosar.
          <ls_row>-fkber = ls_csks-fkber.
        endif.
      endif.

      if <ls_row>-kosar is not initial.
        read table lt_kosar_txt into data(ls_kosar_txt)
          with key kosar = <ls_row>-kosar.
        if sy-subrc = 0.
          <ls_row>-kosar_txt = ls_kosar_txt-ktext.
        endif.
      endif.

      if <ls_row>-fkber is not initial.
        read table lt_fkber_txt into data(ls_fkber_txt)
          with key fkber = <ls_row>-fkber spras = sy-langu.
        if sy-subrc <> 0.
          read table lt_fkber_txt into ls_fkber_txt
            with key fkber = <ls_row>-fkber spras = gc_fallback_langu.
        endif.
        if sy-subrc = 0.
          <ls_row>-fkber_txt = ls_fkber_txt-fkbtx.
        endif.
      endif.

      if <ls_row>-kstar is not initial.
        read table lt_kstar_txt into data(ls_kstar_txt)
          with key kstar = <ls_row>-kstar spras = sy-langu.
        if sy-subrc <> 0.
          read table lt_kstar_txt into ls_kstar_txt
            with key kstar = <ls_row>-kstar spras = gc_fallback_langu.
        endif.
        if sy-subrc = 0.
          <ls_row>-kstar_txt = ls_kstar_txt-ktext.
        endif.
      endif.
    endloop.
  endmethod.


  method build_remark.
*---------------------------------------------------------------------*
* Remark for one SOI line from the non-blocking warnings
*---------------------------------------------------------------------*
* The report showed these warnings once for the whole run (popup or
* status message). A query cannot return messages next to its data,
* so they are attached to the lines they affect instead:
* - a formula line skipped because of a circular/missing reference
* - a rule whose cost center or cost element group did not expand
* - a METHOD A rule while the process order SET was empty
*---------------------------------------------------------------------*
    data lt_parts type string_table.

    read table gt_formula_skipped with table key table_line = iv_soiline
      transporting no fields.
    if sy-subrc = 0.
      append `Formula skipped: circular or missing reference` to lt_parts.
    endif.

    loop at gt_rule into data(ls_rule) where soiline = iv_soiline.
      if ls_rule-ksgru is not initial.
        read table gt_failed_group with table key kind  = 'C'
                                                  kokrs = ls_rule-kokrs
                                                  group = ls_rule-ksgru
          transporting no fields.
        if sy-subrc = 0.
          append |Cost center group { ls_rule-ksgru } not expanded| to lt_parts.
        endif.
      endif.

      if ls_rule-kagru is not initial.
        read table gt_failed_group with table key kind  = 'K'
                                                  kokrs = ls_rule-kokrs
                                                  group = ls_rule-kagru
          transporting no fields.
        if sy-subrc = 0.
          append |Cost element group { ls_rule-kagru } not expanded| to lt_parts.
        endif.
      endif.

      if ls_rule-method = 'A' and gt_order_sets_missing is not initial.
        append |No process orders in SET { concat_lines_of( table = gt_order_sets_missing sep = `, ` ) }|
          to lt_parts.
      endif.
    endloop.

    sort lt_parts.
    delete adjacent duplicates from lt_parts.

    rv_remark = concat_lines_of( table = lt_parts sep = `; ` ).
  endmethod.


  method check_authority.
*---------------------------------------------------------------------*
* Company code authorization (centralised check, display)
*---------------------------------------------------------------------*
* Same call as CHECK_AUTHORITY in Y0000CO_SOI_NEW. The behaviour on a
* failed check is defined in Y0000CO_FI_AUTHORITY_CHECKS.
*---------------------------------------------------------------------*
    data: lv_actvt type c length 2.

    lv_actvt = '03'.

    perform authority_f_bkpf_buk
      in program y0000co_fi_authority_checks
      using gv_bukrs lv_actvt.
  endmethod.


  method add_message.
*---------------------------------------------------------------------*
* Collect a message instead of sending it
*---------------------------------------------------------------------*
* A query provider has no dialog: MESSAGE statements of the report are
* replaced by this method. IV_ERROR stops the run.
*---------------------------------------------------------------------*
    append iv_text to gt_messages.

    if iv_error = abap_true.
      gv_error = abap_true.
      if gv_error_text is initial.
        gv_error_text = iv_text.
      endif.
    endif.
  endmethod.


  method validate_company_code.
*---------------------------------------------------------------------*
* Company code must belong to controlling area 2000
*---------------------------------------------------------------------*
* Same check as VALIDATE_SELECTION_SCREEN of the report (TKA02).
*---------------------------------------------------------------------*
    select single bukrs
      from tka02
      where kokrs = @gc_kokrs
        and bukrs = @gv_bukrs
      into @data(lv_bukrs_chk).

    if sy-subrc <> 0.
      add_message( iv_text  = |Company code { gv_bukrs } not assigned to controlling area { gc_kokrs }|
                   iv_error = abap_true ).
    endif.
  endmethod.


  method read_currency.
*---------------------------------------------------------------------*
* Read the company code currency
*---------------------------------------------------------------------*
    select single waers
      from t001
      where bukrs = @gv_bukrs
      into @gv_waers.

    if sy-subrc <> 0.
      add_message( iv_text  = |Invalid company code { gv_bukrs }|
                   iv_error = abap_true ).
    endif.
  endmethod.


  method read_customizing.
*---------------------------------------------------------------------*
* Read SOI structure, rules and formula customizing
*---------------------------------------------------------------------*
* Every SELECT is restricted to the selected version: reading any of
* these tables without SOIVAR would mix the rows of all versions.
* Text lookup prefers the logon language and falls back to
* GC_FALLBACK_LANGU so a missing translation doesn't drop the line.
* The texts are read INTO TABLE @DATA(...): a SELECT into a pre-typed
* table maps by position, not by name (blank texts in the report).
*---------------------------------------------------------------------*
    select soiline, outline
      from y0000co_nsoi01
      where soivar = @gv_soivar
      order by outline
      into table @data(lt_soi01_base).

    if lt_soi01_base is initial.
      add_message( iv_text  = |No customizing for SOI version { gv_soivar } in Y0000CO_NSOI01|
                   iv_error = abap_true ).
      return.
    endif.

    select soiline, spras, text
      from y0000co_nsoi01t
      for all entries in @lt_soi01_base
      where soivar  = @gv_soivar
        and soiline = @lt_soi01_base-soiline
        and spras in ( @sy-langu, @gc_fallback_langu )
      into table @data(lt_texts).

    clear gt_soi01.
    loop at lt_soi01_base into data(ls_base).
      data(lv_text) = value y0000co_nsoi01t-text( ).

      read table lt_texts into data(ls_text)
        with key soiline = ls_base-soiline spras = sy-langu.
      if sy-subrc <> 0.
        read table lt_texts into ls_text
          with key soiline = ls_base-soiline spras = gc_fallback_langu.
      endif.

      if sy-subrc = 0.
        lv_text = ls_text-text.
      endif.

      append value ty_soi01(
        soiline = ls_base-soiline
        outline = ls_base-outline
        text    = lv_text ) to gt_soi01.
    endloop.

    select soiline,
           method,
           kokrs,
           ksgru,
           kagru
      from y0000co_nsoi02
      where soivar = @gv_soivar
        and kokrs  = @gc_kokrs
        and method in ( 'C', 'A', 'R' )
      into table @gt_rule.

    select soiline, comp_soiline, oper_type
      from y0000co_nsoi03
      where soivar = @gv_soivar
      into table @gt_formula.
  endmethod.


  method validate_customizing.
*---------------------------------------------------------------------*
* Validate customizing consistency
*---------------------------------------------------------------------*
* METHOD A always needs a cost element group, and a SOI line must not
* mix formula rules (R) with extraction rules (C/A): extracted values
* would be silently discarded once APPLY_FORMULA_LINES recalculates
* the line from the formula.
*---------------------------------------------------------------------*
    data lt_soilines type sorted table of y0000co_nsoi02-soiline with unique key table_line.

    loop at gt_rule into data(ls_rule_a) where method = 'A' and kagru is initial.
      add_message( iv_text  = |Method A requires a cost element group in Y0000CO_NSOI02 (SOI line { ls_rule_a-soiline })|
                   iv_error = abap_true ).
    endloop.

    loop at gt_rule into data(ls_rule).
      insert ls_rule-soiline into table lt_soilines.
    endloop.

    loop at lt_soilines into data(lv_soiline).
      data(lv_has_formula)    = abap_false.
      data(lv_has_extraction) = abap_false.

      loop at gt_rule into data(ls_check) where soiline = lv_soiline.
        if ls_check-method = 'R'.
          lv_has_formula = abap_true.
        else.
          lv_has_extraction = abap_true.
        endif.
      endloop.

      if lv_has_formula = abap_true and lv_has_extraction = abap_true.
        add_message( iv_text  = |SOI line { lv_soiline } mixes formula (R) and extraction rules|
                     iv_error = abap_true ).
      endif.
    endloop.
  endmethod.


  method get_set_values.
*---------------------------------------------------------------------*
* Expand a SET via G_SET_TREE_IMPORT
*---------------------------------------------------------------------*
    data: lt_set_values type standard table of setvalues with empty key.

    clear: ct_values, cv_found.

    call function 'G_SET_TREE_IMPORT'
      exporting
        setid      = iv_setid
      tables
        set_values = lt_set_values
      exceptions
        others     = 1.

    if sy-subrc <> 0.
      return.
    endif.

    cv_found = abap_true.

    loop at lt_set_values into data(ls_set).
      append value #( from = ls_set-from
                      to   = ls_set-to ) to ct_values.
    endloop.
  endmethod.


  method resolve_cc_by_group_bukrs.
*---------------------------------------------------------------------*
* Resolve a Cost Center Group to cost centers for the company code
*---------------------------------------------------------------------*
    data: lv_setid       type sethier-setid,
          lt_values      type tt_set_value,
          lt_kostl_range type range of csks-kostl.

    clear: ct_costcenter, cv_found.

    if iv_ksgru is initial.
      return.
    endif.

    concatenate '0101' iv_kokrs iv_ksgru into lv_setid respecting blanks.

    get_set_values(
      exporting iv_setid  = lv_setid
      changing  ct_values = lt_values
                cv_found  = cv_found ).

    if cv_found = abap_false.
      return.
    endif.

    loop at lt_values into data(ls_value).
      if ls_value-from is initial.
        continue.
      endif.

      append value #(
        sign   = 'I'
        option = cond #( when ls_value-to is initial
                           or ls_value-to = ls_value-from
                         then 'EQ'
                         else 'BT' )
        low    = ls_value-from
        high   = cond #( when ls_value-to is initial
                           or ls_value-to = ls_value-from
                         then ''
                         else ls_value-to )
      ) to lt_kostl_range.
    endloop.

    if lt_kostl_range is initial.
      return.
    endif.

    select distinct kostl
      from csks
      where kokrs = @iv_kokrs
        and bukrs = @gv_bukrs
        and kostl in @lt_kostl_range
      into table @data(lt_kostl).

    loop at lt_kostl into data(lv_kostl).
      insert value #( kostl = lv_kostl ) into table ct_costcenter.
    endloop.
  endmethod.


  method build_objnr_from_costcenters.
*---------------------------------------------------------------------*
* Build KS.../KL...* object numbers for a set of cost centers
*---------------------------------------------------------------------*
    data ls_objnr type ty_obj_scope.

    clear ct_objnr.

    loop at it_costcenter into data(ls_cost).
      clear ls_objnr.
      ls_objnr-objnr = |KS{ gc_kokrs }{ ls_cost-kostl }|.
      insert ls_objnr into table ct_objnr.

      clear ls_objnr.
      ls_objnr-objnr = |KL{ gc_kokrs }{ ls_cost-kostl }*|.
      insert ls_objnr into table ct_objnr.
    endloop.
  endmethod.


  method resolve_kstar_group.
*---------------------------------------------------------------------*
* Resolve a Cost Element Group to a KSTAR range
*---------------------------------------------------------------------*
    data: lv_ktopl  type ktopl,
          lv_setid  type sethier-setid,
          lt_values type tt_set_value.

    clear: ct_kstar, cv_found.

    if iv_kagru is initial.
      return.
    endif.

    select single ktopl
      from tka01
      where kokrs = @iv_kokrs
      into @lv_ktopl.

    if sy-subrc <> 0 or lv_ktopl is initial.
      return.
    endif.

    concatenate '0102' lv_ktopl iv_kagru into lv_setid respecting blanks.
    get_set_values(
      exporting iv_setid  = lv_setid
      changing  ct_values = lt_values
                cv_found  = cv_found ).

    if cv_found = abap_false.
      return.
    endif.

    loop at lt_values into data(ls_val) where from is not initial.
      append value #(
        sign   = 'I'
        option = cond #( when ls_val-to is initial
                           or ls_val-to = ls_val-from
                         then 'EQ'
                         else 'BT' )
        low    = ls_val-from
        high   = cond #( when ls_val-to is initial
                           or ls_val-to = ls_val-from
                         then ''
                         else ls_val-to )
      ) to ct_kstar.
    endloop.
  endmethod.


  method prepare_order_scope.
*---------------------------------------------------------------------*
* Read the process order SET (METHOD A object scope)
*---------------------------------------------------------------------*
* SET name pattern INTORD_<BUKRS><GJAHR>.CCSS; SETLEAF-VALFROM holds
* the order number, and the CO object number is built as
* OBJNR = 'OR' + order number. Process orders carry actuals only: a
* plan run (WRTTP <> 04) leaves the cache empty, which also skips
* READ_ORDER_TOTALS and every METHOD A rule in BUILD_SUMMARY_DATA.
*---------------------------------------------------------------------*
    data: lv_setname type setleaf-setname.

    clear gt_order_cache.

    if gv_wrttp <> '04'.
      return.
    endif.

    concatenate 'INTORD_' gv_bukrs gv_gjahr '.CCSS' into lv_setname respecting blanks.

    select valfrom
      from setleaf
      where setname = @lv_setname
        and valfrom <> ''
      into table @data(lt_orders).

    if lt_orders is initial.
      add_message( |No process orders found in SET { lv_setname }| ).
      if not line_exists( gt_order_sets_missing[ table_line = conv string( lv_setname ) ] ).
        append conv string( lv_setname ) to gt_order_sets_missing.
      endif.
      return.
    endif.

    loop at lt_orders into data(ls_order).
      insert value #(
        bukrs = gv_bukrs
        gjahr = gv_gjahr
        objnr = |OR{ ls_order-valfrom }| ) into table gt_order_cache.
    endloop.
  endmethod.


  method read_order_totals.
*---------------------------------------------------------------------*
* Read COSP/COSS totals for the whole process order SET
*---------------------------------------------------------------------*
* Reads once for the whole run, independent of KAGRU, in batches of
* GC_ORDER_BATCH_SIZE orders (see READ_ORDER_TOTALS_BATCH). The KSTAR
* range is narrowed to the groups any METHOD A rule needs; it unions
* ranges across METHOD A rules, which is safe because only ONE object
* scope (the order SET) is read here.
*---------------------------------------------------------------------*
    constants gc_order_batch_size type i value 5000.

    data: lt_r_kstar type tt_r_kstar,
          lt_r_objnr type tt_r_objnr.

    clear gt_order_totals.

    if gt_order_cache is initial.
      return.
    endif.

    loop at gt_rule into data(ls_rule_a) where method = 'A'.
      loop at gt_kstar_cache into data(ls_kstar_a)
        where kokrs = ls_rule_a-kokrs and kagru = ls_rule_a-kagru.
        append value #(
          sign   = ls_kstar_a-sign
          option = ls_kstar_a-option
          low    = ls_kstar_a-low
          high   = ls_kstar_a-high ) to lt_r_kstar.
      endloop.
    endloop.

    sort lt_r_kstar.
    delete adjacent duplicates from lt_r_kstar comparing all fields.

    if lt_r_kstar is initial.
      return.
    endif.

    loop at gt_order_cache into data(ls_order_scope).
      append value #( sign = 'I' option = 'EQ' low = ls_order_scope-objnr ) to lt_r_objnr.

      if lines( lt_r_objnr ) >= gc_order_batch_size.
        read_order_totals_batch(
          it_r_objnr = lt_r_objnr
          it_r_kstar = lt_r_kstar ).
        clear lt_r_objnr.
      endif.
    endloop.

    if lt_r_objnr is not initial.
      read_order_totals_batch(
        it_r_objnr = lt_r_objnr
        it_r_kstar = lt_r_kstar ).
    endif.
  endmethod.


  method read_order_totals_batch.
*---------------------------------------------------------------------*
* Read one batch of the process order OBJNR range
*---------------------------------------------------------------------*
* Plain row fetch summed in ABAP - GROUP BY/SUM() was tried in the
* report and reverted because it does not scale with large order
* counts. If the WHERE clause is too large for the database interface
* (DBSQL_STMNT_TOO_LARGE), the batch is split in half and each half is
* retried recursively; any other Open SQL DB error is re-raised.
*---------------------------------------------------------------------*
    data: lv_half      type i,
          lt_r_objnr_a type tt_r_objnr,
          lt_r_objnr_b type tt_r_objnr.

    try.
        select objnr, kstar,
               wog001, wog002, wog003, wog004,
               wog005, wog006, wog007, wog008,
               wog009, wog010, wog011, wog012,
               wog013, wog014, wog015, wog016
          from v_coss_view
          where lednr = @gc_lednr
            and gjahr = @gv_gjahr
            and wrttp = @gv_wrttp
            and versn = @gv_versn
            and kstar in @it_r_kstar
            and objnr in @it_r_objnr
            and (
                 wog001 <> 0 or wog002 <> 0 or
                 wog003 <> 0 or wog004 <> 0 or
                 wog005 <> 0 or wog006 <> 0 or
                 wog007 <> 0 or wog008 <> 0 or
                 wog009 <> 0 or wog010 <> 0 or
                 wog011 <> 0 or wog012 <> 0 or
                 wog013 <> 0 or wog014 <> 0 or
                 wog015 <> 0 or wog016 <> 0
            )
          into table @data(lt_coss).

        loop at lt_coss into data(ls_coss).
          insert corresponding #( ls_coss ) into table gt_order_totals.
        endloop.

        select objnr, kstar,
               wog001, wog002, wog003, wog004,
               wog005, wog006, wog007, wog008,
               wog009, wog010, wog011, wog012,
               wog013, wog014, wog015, wog016
          from v_cosp_view
          where lednr = @gc_lednr
            and gjahr = @gv_gjahr
            and wrttp = @gv_wrttp
            and versn = @gv_versn
            and kstar in @it_r_kstar
            and objnr in @it_r_objnr
            and (
                 wog001 <> 0 or wog002 <> 0 or
                 wog003 <> 0 or wog004 <> 0 or
                 wog005 <> 0 or wog006 <> 0 or
                 wog007 <> 0 or wog008 <> 0 or
                 wog009 <> 0 or wog010 <> 0 or
                 wog011 <> 0 or wog012 <> 0 or
                 wog013 <> 0 or wog014 <> 0 or
                 wog015 <> 0 or wog016 <> 0
            )
          into table @data(lt_cosp).

        loop at lt_cosp into data(ls_cosp).
          insert corresponding #( ls_cosp ) into table gt_order_totals.
        endloop.

      catch cx_sy_open_sql_db into data(lx_sql).
        if lx_sql->kernel_errid = 'DBSQL_STMNT_TOO_LARGE' and lines( it_r_objnr ) > 1.
          lv_half = lines( it_r_objnr ) / 2.
          append lines of it_r_objnr from 1 to lv_half to lt_r_objnr_a.
          append lines of it_r_objnr from lv_half + 1 to lines( it_r_objnr ) to lt_r_objnr_b.

          read_order_totals_batch(
            it_r_objnr = lt_r_objnr_a
            it_r_kstar = it_r_kstar ).
          read_order_totals_batch(
            it_r_objnr = lt_r_objnr_b
            it_r_kstar = it_r_kstar ).
        else.
          raise exception lx_sql.
        endif.
    endtry.
  endmethod.


  method periods_from_wog.
*---------------------------------------------------------------------*
* Copy WOGnnn columns into a VALnnn period structure
*---------------------------------------------------------------------*
    data lv_period type ty_period.

    field-symbols: <lv_src> type any,
                   <lv_tgt> type any.

    clear cs_periods.

    do 16 times.
      lv_period = sy-index.

      assign component |WOG{ lv_period }| of structure iv_source to <lv_src>.
      if sy-subrc <> 0.
        continue.
      endif.

      assign component |VAL{ lv_period }| of structure cs_periods to <lv_tgt>.
      if sy-subrc <> 0.
        continue.
      endif.

      <lv_tgt> = <lv_src>.
    enddo.
  endmethod.


  method accumulate_periods.
*---------------------------------------------------------------------*
* Add one period structure into a running total
*---------------------------------------------------------------------*
    data lv_period type ty_period.

    field-symbols: <lv_add> type any,
                   <lv_tot> type any.

    do 16 times.
      lv_period = sy-index.

      assign component |VAL{ lv_period }| of structure is_add to <lv_add>.
      assign component |VAL{ lv_period }| of structure cs_total to <lv_tot>.
      if sy-subrc = 0.
        <lv_tot> = <lv_tot> + <lv_add>.
      endif.
    enddo.
  endmethod.


  method add_periods_to_summary.
*---------------------------------------------------------------------*
* Accumulate a period structure into the SOI summary line
*---------------------------------------------------------------------*
* Only the periods GV_PERV to GV_PERB are added.
*---------------------------------------------------------------------*
    data lv_period type ty_period.

    field-symbols: <lv_src> type any,
                   <lv_tgt> type any.

    do gv_perb times.
      if sy-index < gv_perv.
        continue.
      endif.

      lv_period = sy-index.

      assign component |VAL{ lv_period }| of structure is_periods to <lv_src>.
      if sy-subrc <> 0.
        continue.
      endif.

      assign component |VAL{ lv_period }| of structure cs_summary to <lv_tgt>.
      if sy-subrc <> 0.
        continue.
      endif.

      <lv_tgt> = <lv_tgt> + <lv_src>.
    enddo.
  endmethod.


  method select_totals_for_rule.
*---------------------------------------------------------------------*
* Read and accumulate COSP/COSS totals for one extraction rule
*---------------------------------------------------------------------*
* METHOD A rules filter the already-read GT_ORDER_TOTALS in memory by
* KSTAR instead of querying the database again. Other methods query
* COSP/COSS scoped ONLY to this rule's own OBJNR/KSTAR ranges - never
* unioned with other rules (reverted in the report: cross-product and
* slower). GT_TOTALS_CACHE avoids redundant work when several SOI
* lines share an identical rule.
*---------------------------------------------------------------------*
    data: lt_r_objnr       type tt_r_objnr,
          ls_periods       type ty_period_sum,
          ls_periods_total type ty_period_sum,
          ls_cache_entry   type ty_totals_cache.

    field-symbols <ls_objnr_range> like line of lt_r_objnr.

    if it_objnr is initial or it_kstar is initial.
      return.
    endif.

    ls_cache_entry-method = is_rule-method.
    ls_cache_entry-kokrs  = is_rule-kokrs.
    ls_cache_entry-bukrs  = iv_bukrs.
    ls_cache_entry-ksgru  = is_rule-ksgru.
    ls_cache_entry-kagru  = is_rule-kagru.

    read table gt_totals_cache into data(ls_cached)
      with table key method = ls_cache_entry-method
                     kokrs  = ls_cache_entry-kokrs
                     bukrs  = ls_cache_entry-bukrs
                     ksgru  = ls_cache_entry-ksgru
                     kagru  = ls_cache_entry-kagru.

    if sy-subrc = 0.
      add_periods_to_summary(
        exporting is_periods = ls_cached-periods
        changing  cs_summary = cs_summary ).
      return.
    endif.

    if is_rule-method = 'A'.
      loop at gt_order_totals into data(ls_order_row) where kstar in it_kstar.
        periods_from_wog(
          exporting iv_source  = ls_order_row
          changing  cs_periods = ls_periods ).
        accumulate_periods(
          exporting is_add   = ls_periods
          changing  cs_total = ls_periods_total ).
      endloop.

    else.
      loop at it_objnr into data(ls_objnr).
        append initial line to lt_r_objnr assigning <ls_objnr_range>.

        <ls_objnr_range>-sign = 'I'.

        case ls_objnr-objnr(2).
          when 'KL'.
            <ls_objnr_range>-option = 'CP'.
          when others.
            <ls_objnr_range>-option = 'EQ'.
        endcase.

        <ls_objnr_range>-low = ls_objnr-objnr.
      endloop.

      if lt_r_objnr is initial.
        return.
      endif.

      select objnr, kstar,
             wog001, wog002, wog003, wog004,
             wog005, wog006, wog007, wog008,
             wog009, wog010, wog011, wog012,
             wog013, wog014, wog015, wog016
        from v_coss_view
        where lednr = @gc_lednr
          and gjahr = @gv_gjahr
          and wrttp = @gv_wrttp
          and versn = @gv_versn
          and kstar in @it_kstar
          and objnr in @lt_r_objnr
          and (
               wog001 <> 0 or wog002 <> 0 or
               wog003 <> 0 or wog004 <> 0 or
               wog005 <> 0 or wog006 <> 0 or
               wog007 <> 0 or wog008 <> 0 or
               wog009 <> 0 or wog010 <> 0 or
               wog011 <> 0 or wog012 <> 0 or
               wog013 <> 0 or wog014 <> 0 or
               wog015 <> 0 or wog016 <> 0
          )
        into table @data(lt_coss).

      loop at lt_coss into data(ls_coss).
        periods_from_wog(
          exporting iv_source  = ls_coss
          changing  cs_periods = ls_periods ).
        accumulate_periods(
          exporting is_add   = ls_periods
          changing  cs_total = ls_periods_total ).
      endloop.

      select objnr, kstar,
             wog001, wog002, wog003, wog004,
             wog005, wog006, wog007, wog008,
             wog009, wog010, wog011, wog012,
             wog013, wog014, wog015, wog016
        from v_cosp_view
        where lednr = @gc_lednr
          and gjahr = @gv_gjahr
          and wrttp = @gv_wrttp
          and versn = @gv_versn
          and kstar in @it_kstar
          and objnr in @lt_r_objnr
          and (
               wog001 <> 0 or wog002 <> 0 or
               wog003 <> 0 or wog004 <> 0 or
               wog005 <> 0 or wog006 <> 0 or
               wog007 <> 0 or wog008 <> 0 or
               wog009 <> 0 or wog010 <> 0 or
               wog011 <> 0 or wog012 <> 0 or
               wog013 <> 0 or wog014 <> 0 or
               wog015 <> 0 or wog016 <> 0
          )
        into table @data(lt_cosp).

      loop at lt_cosp into data(ls_cosp).
        periods_from_wog(
          exporting iv_source  = ls_cosp
          changing  cs_periods = ls_periods ).
        accumulate_periods(
          exporting is_add   = ls_periods
          changing  cs_total = ls_periods_total ).
      endloop.
    endif.

    ls_cache_entry-periods = ls_periods_total.
    insert ls_cache_entry into table gt_totals_cache.

    add_periods_to_summary(
      exporting is_periods = ls_periods_total
      changing  cs_summary = cs_summary ).
  endmethod.


  method prepare_rule_scopes.
*---------------------------------------------------------------------*
* Build all cached object number / KSTAR scopes for every rule
*---------------------------------------------------------------------*
* Each distinct (KOKRS/BUKRS/KSGRU) or (KOKRS/KAGRU) combination is
* expanded only once per run (the one-SET-expansion rule). Nothing
* here depends on fiscal year, version or value type: the SETs are
* read without a key date and CSKS is not filtered on validity. Must
* run before READ_ORDER_TOTALS, which narrows the order read using
* GT_KSTAR_CACHE. A group that fails to expand is reported as a
* message (non-blocking), like REPORT_SET_ERRORS in the report.
*---------------------------------------------------------------------*
    data: lt_costcenter type tt_kostl_scope,
          lt_objnr      type tt_obj_scope,
          lt_kstar      type tt_r_kstar,
          lv_found      type abap_bool.

    clear:
      gt_cc_cache,
      gt_kstar_cache.

    loop at gt_rule into data(ls_rule).
      if ls_rule-method = 'R'.
        continue.
      endif.

      if ls_rule-ksgru is not initial.
        read table gt_cc_cache with key kokrs = ls_rule-kokrs
                                        bukrs = gv_bukrs
                                        ksgru = ls_rule-ksgru
                               transporting no fields.
        if sy-subrc <> 0.
          clear: lt_costcenter, lt_objnr.

          resolve_cc_by_group_bukrs(
            exporting iv_kokrs      = ls_rule-kokrs
                      iv_ksgru      = ls_rule-ksgru
            changing  ct_costcenter = lt_costcenter
                      cv_found      = lv_found ).

          if lv_found = abap_false.
            add_message( |Cost center group { ls_rule-ksgru } (KOKRS { ls_rule-kokrs }) could not be expanded| ).
            insert value #( kind = 'C' kokrs = ls_rule-kokrs group = ls_rule-ksgru )
              into table gt_failed_group.
          endif.

          build_objnr_from_costcenters(
            exporting it_costcenter = lt_costcenter
            changing  ct_objnr      = lt_objnr ).

          loop at lt_objnr into data(ls_objnr).
            insert value ty_cc_cache(
              kokrs = ls_rule-kokrs
              bukrs = gv_bukrs
              ksgru = ls_rule-ksgru
              objnr = ls_objnr-objnr ) into table gt_cc_cache.
          endloop.
        endif.
      endif.

      if ls_rule-kagru is not initial.
        read table gt_kstar_cache with key kokrs = ls_rule-kokrs
                                           kagru = ls_rule-kagru
                                  transporting no fields.
        if sy-subrc <> 0.
          clear lt_kstar.

          resolve_kstar_group(
            exporting iv_kokrs = ls_rule-kokrs
                      iv_kagru = ls_rule-kagru
            changing  ct_kstar = lt_kstar
                      cv_found = lv_found ).

          if lv_found = abap_false.
            add_message( |Cost element group { ls_rule-kagru } (KOKRS { ls_rule-kokrs }) could not be expanded| ).
            insert value #( kind = 'K' kokrs = ls_rule-kokrs group = ls_rule-kagru )
              into table gt_failed_group.
          endif.

          loop at lt_kstar into data(ls_kstar).
            insert value ty_kstar_cache(
              kokrs  = ls_rule-kokrs
              kagru  = ls_rule-kagru
              sign   = ls_kstar-sign
              option = ls_kstar-option
              low    = ls_kstar-low
              high   = ls_kstar-high ) into table gt_kstar_cache.
          endloop.
        endif.
      endif.

    endloop.
  endmethod.


  method get_cached_objnr.
*---------------------------------------------------------------------*
* Look up cached cost center object numbers for one rule
*---------------------------------------------------------------------*
    clear ct_objnr.

    loop at gt_cc_cache into data(ls_cc_cache)
      where kokrs = iv_kokrs
        and bukrs = iv_bukrs
        and ksgru = iv_ksgru.
      insert value #( objnr = ls_cc_cache-objnr ) into table ct_objnr.
    endloop.
  endmethod.


  method get_cached_order_objnr.
*---------------------------------------------------------------------*
* Look up cached process order object numbers
*---------------------------------------------------------------------*
    clear ct_objnr.

    loop at gt_order_cache into data(ls_order_cache)
      where bukrs = gv_bukrs
        and gjahr = gv_gjahr.
      insert value #( objnr = ls_order_cache-objnr ) into table ct_objnr.
    endloop.
  endmethod.


  method get_cached_kstar.
*---------------------------------------------------------------------*
* Look up the cached KSTAR range for one rule
*---------------------------------------------------------------------*
    clear ct_kstar.

    loop at gt_kstar_cache into data(ls_kstar_cache)
      where kokrs = iv_kokrs
        and kagru = iv_kagru.
      append value #(
        sign   = ls_kstar_cache-sign
        option = ls_kstar_cache-option
        low    = ls_kstar_cache-low
        high   = ls_kstar_cache-high ) to ct_kstar.
    endloop.
  endmethod.


  method build_summary_data.
*---------------------------------------------------------------------*
* Build the SOI summary table from every rule's accumulated totals
*---------------------------------------------------------------------*
* Same logic as the report, without the ALV colour column.
*---------------------------------------------------------------------*
    data: ls_summary type ty_summary,
          lt_objnr   type tt_obj_scope,
          lt_kstar   type tt_r_kstar.

    clear gt_summary.

    loop at gt_soi01 into data(ls_soi01).
      clear ls_summary.
      ls_summary-soiline = ls_soi01-soiline.
      ls_summary-outline = ls_soi01-outline.
      ls_summary-text    = ls_soi01-text.
      ls_summary-waers   = gv_waers.

      loop at gt_rule into data(ls_rule) where soiline = ls_soi01-soiline.
        if ls_rule-method = 'R'.
          ls_summary-is_formula = abap_true.
          continue.
        endif.

        clear: lt_objnr, lt_kstar.

        if ls_rule-method = 'A'.

          if gv_wrttp <> '04'.
            continue.
          endif.

          get_cached_order_objnr( changing ct_objnr = lt_objnr ).

        else.

          get_cached_objnr(
            exporting iv_kokrs = ls_rule-kokrs
                      iv_bukrs = gv_bukrs
                      iv_ksgru = ls_rule-ksgru
            changing  ct_objnr = lt_objnr ).

        endif.

        get_cached_kstar(
          exporting iv_kokrs = ls_rule-kokrs
                    iv_kagru = ls_rule-kagru
          changing  ct_kstar = lt_kstar ).

        if lt_objnr is initial or lt_kstar is initial.
          continue.
        endif.

        select_totals_for_rule(
          exporting is_rule    = ls_rule
                    iv_bukrs   = gv_bukrs
                    it_objnr   = lt_objnr
                    it_kstar   = lt_kstar
          changing  cs_summary = ls_summary ).
      endloop.

      if ls_summary-is_formula = abap_false.
        ls_summary-line_sum =
            ls_summary-val001 + ls_summary-val002 + ls_summary-val003 + ls_summary-val004 +
            ls_summary-val005 + ls_summary-val006 + ls_summary-val007 + ls_summary-val008 +
            ls_summary-val009 + ls_summary-val010 + ls_summary-val011 + ls_summary-val012 +
            ls_summary-val013 + ls_summary-val014 + ls_summary-val015 + ls_summary-val016.
      endif.

      append ls_summary to gt_summary.
    endloop.
  endmethod.


  method apply_formula_lines.
*---------------------------------------------------------------------*
* Resolve METHOD R formula lines in dependency order
*---------------------------------------------------------------------*
* Multi-pass resolution: a formula line is only calculated once every
* SOI line it references (extraction or formula) is already resolved,
* so formulas may reference other formulas regardless of OUTLINE.
* Lines left unresolved after a pass with no progress have a circular
* or missing reference; they are reported and left at zero.
*---------------------------------------------------------------------*
    types tt_soiline type sorted table of y0000co_nsoi01-soiline with unique key table_line.

    data:
      lt_resolved           type tt_soiline,
      lt_pending            type standard table of y0000co_nsoi01-soiline with empty key,
      lt_resolved_this_pass type standard table of y0000co_nsoi01-soiline with empty key,
      lv_changed            type abap_bool,
      lv_ready              type abap_bool,
      lv_period_num         type n length 3,
      lv_period             type ty_period.

    field-symbols:
      <ls_sum> type ty_summary,
      <ls_cmp> type ty_summary,
      <lv_tgt> type any,
      <lv_src> type any.

    loop at gt_summary into data(ls_seed) where is_formula = abap_false.
      insert ls_seed-soiline into table lt_resolved.
    endloop.

    loop at gt_summary into data(ls_formula_line) where is_formula = abap_true.
      append ls_formula_line-soiline to lt_pending.
    endloop.

    do.
      lv_changed = abap_false.
      clear lt_resolved_this_pass.

      loop at lt_pending into data(lv_soiline).
        lv_ready = abap_true.

        loop at gt_formula into data(ls_formula_dep) where soiline = lv_soiline.
          read table lt_resolved with table key table_line = ls_formula_dep-comp_soiline
            transporting no fields.
          if sy-subrc <> 0.
            lv_ready = abap_false.
            exit.
          endif.
        endloop.

        if lv_ready = abap_false.
          continue.
        endif.

        read table gt_summary assigning <ls_sum> with key soiline = lv_soiline.
        if sy-subrc <> 0.
          append lv_soiline to lt_resolved_this_pass.
          lv_changed = abap_true.
          continue.
        endif.

        clear: <ls_sum>-val001, <ls_sum>-val002, <ls_sum>-val003, <ls_sum>-val004,
               <ls_sum>-val005, <ls_sum>-val006, <ls_sum>-val007, <ls_sum>-val008,
               <ls_sum>-val009, <ls_sum>-val010, <ls_sum>-val011, <ls_sum>-val012,
               <ls_sum>-val013, <ls_sum>-val014, <ls_sum>-val015, <ls_sum>-val016,
               <ls_sum>-line_sum.

        loop at gt_formula into data(ls_formula) where soiline = lv_soiline.
          read table gt_summary assigning <ls_cmp> with key soiline = ls_formula-comp_soiline.
          if sy-subrc <> 0.
            continue.
          endif.

          do gv_perb times.
            if sy-index < gv_perv.
              continue.
            endif.

            lv_period_num = sy-index.
            lv_period = lv_period_num.

            assign component |VAL{ lv_period }| of structure <ls_sum> to <lv_tgt>.
            if sy-subrc <> 0.
              continue.
            endif.

            assign component |VAL{ lv_period }| of structure <ls_cmp> to <lv_src>.
            if sy-subrc <> 0.
              continue.
            endif.

            case ls_formula-oper_type.
              when '+'.
                <lv_tgt> = <lv_tgt> + <lv_src>.
              when '-'.
                <lv_tgt> = <lv_tgt> - <lv_src>.
            endcase.
          enddo.
        endloop.

        <ls_sum>-line_sum =
          <ls_sum>-val001 + <ls_sum>-val002 + <ls_sum>-val003 + <ls_sum>-val004 +
          <ls_sum>-val005 + <ls_sum>-val006 + <ls_sum>-val007 + <ls_sum>-val008 +
          <ls_sum>-val009 + <ls_sum>-val010 + <ls_sum>-val011 + <ls_sum>-val012 +
          <ls_sum>-val013 + <ls_sum>-val014 + <ls_sum>-val015 + <ls_sum>-val016.

        append lv_soiline to lt_resolved_this_pass.
        lv_changed = abap_true.
      endloop.

      loop at lt_resolved_this_pass into lv_soiline.
        insert lv_soiline into table lt_resolved.
        delete lt_pending where table_line = lv_soiline.
      endloop.

      if lt_pending is initial.
        exit.
      endif.

      if lv_changed = abap_false.
        loop at lt_pending into lv_soiline.
          add_message( |Formula SOI line { lv_soiline } skipped: circular/missing reference| ).
          insert lv_soiline into table gt_formula_skipped.
        endloop.
        exit.
      endif.
    enddo.
  endmethod.

endclass.
