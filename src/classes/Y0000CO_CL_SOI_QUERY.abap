*----------------------------------------------------------------------*
* Description : Query provider for the SOI Fiori preview
*----------------------------------------------------------------------*
* ABAP Name     : Y0000CO_CL_SOI_QUERY
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
*  Fills the custom entities of the Fiori preview of the Statement of
*  Income (SOI):
*  - Y0000CO_C_SOILINE: one row per SOI line (list)
*  - Y0000CO_C_SOIDET : the breakdown of one SOI line (detail page)
*  - Y0000CO_C_SOIITM : the line items of one breakdown row (COEP/COEJ)
*
*  The values come from the SOI engine Y0000CO_CL_SOI_ENGINE, a copy
*  of the engine of report Y0000CO_SOI_NEW: periods 1-12, special
*  periods 13-16, total over the period range, and the comparison
*  against a second data set when a comparison field is filled. The
*  breakdown is the report's double-click drill-down: cost center /
*  order / cost element rows for an extraction line, formula
*  components for a formula line.
*
*  Typical business use:
*  Controllers open the SOI preview, select version, year and company
*  code, read the statement lines and click a line for its breakdown.
*
*  Main Steps
*  1. Read the filter values of the request
*  2. Run the SOI engine for the selection
*  3. Map the engine lines (or the breakdown of one line) to the rows
*  4. Apply sorting and paging, return the rows and the total count
*
*  Important technical notes from development:
*  - Controlling area (KOKRS) is fixed to '2000' (in the engine)
*  - Authorization is checked first in the engine's RUN, with the
*    centralised Y0000CO_FI_AUTHORITY_CHECKS, as in the report
*  - Texts (logon language, fallback 'E') come from the engine
*  - One class serves all three entities; GET_ENTITY_ID tells which
*  - The breakdown request runs the engine again (no state is kept
*    between OData requests); the filter carries all keys of the line
*  - Comments must stay inside METHOD ... ENDMETHOD: the class editor
*    rejects comments between method implementations
*  - The framework expects sorting and paging to be read by the query
*    provider; both are applied in memory
*  - CX_RAP_QUERY_PROVIDER is abstract and cannot be raised; blocking
*    engine errors are raised as Y0000CO_CX_SOI
*----------------------------------------------------------------------*
class y0000co_cl_soi_query definition
  public
  final
  create public.

  public section.
    interfaces if_rap_query_provider.

  private section.

*---------------------------------------------------------------------*
* Filter values of one request
*---------------------------------------------------------------------*
* Only the first single value of each filter is used. SOILINE and the
* breakdown keys (COSTCENTER ... COMPONENTLINE) arrive when the
* framework reads one row by its key or follows the association from
* a SOI line to its breakdown.
*---------------------------------------------------------------------*
    types:
      begin of ty_filter,
        soivar   type y0000co_nsoi00-soivar,
        gjahr    type gjahr,
        bukrs    type bukrs,
        wrttp    type wrttp,
        versn    type versn,
        perv     type monat,
        perb     type monat,
        gjahr2   type gjahr,
        versn2   type versn,
        wrttp2   type wrttp,
        soiline  type y0000co_nsoi01-soiline,
        kostl    type kostl,
        aufnr    type aufnr,
        kstar    type kstar,
        comp_soiline type y0000co_nsoi01-soiline,
        data_set type c length 10,
        belnr    type c length 10,
        buzei    type n length 3,
        perio    type n length 3,
      end of ty_filter.

*---------------------------------------------------------------------*
* Result table types
*---------------------------------------------------------------------*
* Named table types are needed: generic table types cannot be used in
* RETURNING parameters.
*---------------------------------------------------------------------*
    types:
      tt_result type standard table of y0000co_c_soiline with empty key,
      tt_detail type standard table of y0000co_c_soidet with empty key,
      tt_item   type standard table of y0000co_c_soiitm with empty key.

    methods:
      read_filter
        importing io_request       type ref to if_rap_query_request
        returning value(rs_filter) type ty_filter
        raising   cx_rap_query_filter_no_range,

      run_engine
        importing is_filter        type ty_filter
        returning value(ro_engine) type ref to y0000co_cl_soi_engine
        raising   y0000co_cx_soi,

      read_lines
        importing is_filter        type ty_filter
        returning value(rt_result) type tt_result
        raising   y0000co_cx_soi,

      read_details
        importing is_filter        type ty_filter
        returning value(rt_detail) type tt_detail
        raising   y0000co_cx_soi,

      read_items
        importing is_filter      type ty_filter
        returning value(rt_item) type tt_item
        raising   y0000co_cx_soi,

      build_context
        importing is_filter         type ty_filter
        returning value(rs_context) type y0000co_cl_soi_engine=>ty_context,

      respond
        importing io_request  type ref to if_rap_query_request
                  io_response type ref to if_rap_query_response
        changing  ct_result   type standard table.

endclass.


class y0000co_cl_soi_query implementation.

  method if_rap_query_provider~select.
*---------------------------------------------------------------------*
* Select: entry point called by the RAP framework
*---------------------------------------------------------------------*
* One class implements both custom entities, so the entity name of the
* request decides what is read. CX_RAP_QUERY_FILTER_NO_RANGE from
* READ_FILTER and Y0000CO_CX_SOI from the engine are not caught: they
* pass through to the framework, which shows them as error messages.
*---------------------------------------------------------------------*

    data(ls_filter) = read_filter( io_request ).

    case to_upper( io_request->get_entity_id( ) ).
      when 'Y0000CO_C_SOIDET'.
        data(lt_detail) = read_details( ls_filter ).
        respond( exporting io_request  = io_request
                           io_response = io_response
                 changing  ct_result   = lt_detail ).

      when 'Y0000CO_C_SOIITM'.
        data(lt_item) = read_items( ls_filter ).
        respond( exporting io_request  = io_request
                           io_response = io_response
                 changing  ct_result   = lt_item ).

      when others.
        data(lt_result) = read_lines( ls_filter ).
        respond( exporting io_request  = io_request
                           io_response = io_response
                 changing  ct_result   = lt_result ).
    endcase.

  endmethod.


  method read_filter.
*---------------------------------------------------------------------*
* Read the filter values of the request
*---------------------------------------------------------------------*
* Defaults match the entity annotations and the classic report
* (SOIVAR STD, value type 04, version 000), so a request without them
* still behaves like the report with its defaults. Filter element
* names arrive in upper case (SOIVERSION, FISCALYEAR, ...).
*---------------------------------------------------------------------*

    data(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).

    rs_filter-soivar = 'STD'.
    rs_filter-wrttp  = '04'.
    rs_filter-versn  = '000'.

    loop at lt_ranges assigning field-symbol(<ls_range>).
      read table <ls_range>-range index 1 into data(ls_value).
      if sy-subrc <> 0.
        continue.
      endif.

      case to_upper( <ls_range>-name ).
        when 'SOIVERSION'.
          rs_filter-soivar = ls_value-low.
        when 'FISCALYEAR'.
          rs_filter-gjahr = ls_value-low.
        when 'COMPANYCODE'.
          rs_filter-bukrs = ls_value-low.
        when 'VALUETYPE'.
          rs_filter-wrttp = ls_value-low.
        when 'VERSION'.
          rs_filter-versn = ls_value-low.
        when 'PERIODFROM'.
          rs_filter-perv = ls_value-low.
        when 'PERIODTO'.
          rs_filter-perb = ls_value-low.
        when 'COMPAREYEAR'.
          rs_filter-gjahr2 = ls_value-low.
        when 'COMPAREVERSION'.
          rs_filter-versn2 = ls_value-low.
        when 'COMPAREVALUETYPE'.
          rs_filter-wrttp2 = ls_value-low.
        when 'SOILINE'.
          rs_filter-soiline = ls_value-low.
        when 'COSTCENTER'.
          rs_filter-kostl = ls_value-low.
        when 'ORDERNUMBER'.
          rs_filter-aufnr = ls_value-low.
        when 'COSTELEMENT'.
          rs_filter-kstar = ls_value-low.
        when 'COMPONENTLINE'.
          rs_filter-comp_soiline = ls_value-low.
        when 'DATASET'.
          rs_filter-data_set = ls_value-low.
        when 'DOCUMENTNUMBER'.
          rs_filter-belnr = ls_value-low.
        when 'DOCUMENTITEM'.
          rs_filter-buzei = ls_value-low.
        when 'FISCALPERIOD'.
          rs_filter-perio = ls_value-low.
      endcase.
    endloop.

  endmethod.


  method run_engine.
*---------------------------------------------------------------------*
* Run the SOI engine for the filter values
*---------------------------------------------------------------------*
* The engine is created per request: its caches live for one run only.
* A blocking engine error is
* raised as Y0000CO_CX_SOI; CL_MESSAGE_HELPER splits its text into
* SY-MSGV1-4 for message 00/398 (& & & &).
*---------------------------------------------------------------------*

    ro_engine = new y0000co_cl_soi_engine( ).

    ro_engine->run( build_context( is_filter ) ).

    data(lv_error) = ro_engine->get_error( ).
    if lv_error is not initial.
      cl_message_helper=>set_msg_vars_for_clike( lv_error ).
      raise exception type y0000co_cx_soi
        message e398(00) with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    endif.

  endmethod.


  method read_lines.
*---------------------------------------------------------------------*
* SOI lines for the list (entity Y0000CO_C_SOILINE)
*---------------------------------------------------------------------*
* Without company code or fiscal year there is nothing to compute (both
* are mandatory in the filter bar, so this is only a safeguard). The
* filter values are copied back into the key fields of every row, so
* the detail page (which reads one row by its key) and the breakdown
* (which follows the association on those keys) get the same numbers.
* Warnings arrive as the REMARK of the affected lines.
*---------------------------------------------------------------------*

    data: lv_period3 type n length 3,
          lv_period2 type n length 2.

    field-symbols: <lv_src> type any,
                   <lv_tgt> type any.

    if is_filter-bukrs is initial or is_filter-gjahr is initial.
      return.
    endif.

    data(lo_engine) = run_engine( is_filter ).
    data(lt_lines)  = lo_engine->get_lines( ).

    loop at lt_lines assigning field-symbol(<ls_line>).
      if is_filter-soiline is not initial and <ls_line>-soiline <> is_filter-soiline.
        continue.
      endif.

      data(ls_row) = value y0000co_c_soiline(
        soiversion        = is_filter-soivar
        fiscalyear        = is_filter-gjahr
        companycode       = is_filter-bukrs
        valuetype         = is_filter-wrttp
        version           = is_filter-versn
        periodfrom        = is_filter-perv
        periodto          = is_filter-perb
        compareyear       = is_filter-gjahr2
        compareversion    = is_filter-versn2
        comparevaluetype  = is_filter-wrttp2
        soiline           = <ls_line>-soiline
        soilinetext       = <ls_line>-text
        outline           = <ls_line>-outline
        totalamount       = <ls_line>-total
        compareamount     = <ls_line>-total_cmp
        differenceamount  = <ls_line>-diff_abs
        differencepercent = <ls_line>-diff_pct
        specialperiods    = <ls_line>-special
        remark            = <ls_line>-remark
        currency          = <ls_line>-waers ).

*     Period columns: VAL001-VAL012 of the engine line into
*     PERIOD01-PERIOD12 of the row.
      do 12 times.
        lv_period3 = sy-index.
        lv_period2 = sy-index.
        assign component |VAL{ lv_period3 }| of structure <ls_line> to <lv_src>.
        assign component |PERIOD{ lv_period2 }| of structure ls_row to <lv_tgt>.
        if <lv_src> is assigned and <lv_tgt> is assigned.
          <lv_tgt> = <lv_src>.
        endif.
        unassign: <lv_src>, <lv_tgt>.
      enddo.

      append ls_row to rt_result.
    endloop.

  endmethod.


  method read_details.
*---------------------------------------------------------------------*
* Breakdown of one SOI line (entity Y0000CO_C_SOIDET)
*---------------------------------------------------------------------*
* Called when the detail page of a SOI line follows the association
* _DETAILS: the filter carries all keys of the line, including
* SOILINE. Without SOILINE (a direct call of the breakdown entity set)
* nothing is returned, because a breakdown always belongs to a line.
* The breakdown keys in the filter are only set when one breakdown row
* is read by its key; then only that row is returned.
*---------------------------------------------------------------------*

    data: lv_period3 type n length 3,
          lv_period2 type n length 2.

    field-symbols: <lv_src> type any,
                   <lv_tgt> type any.

    if is_filter-bukrs is initial or is_filter-gjahr is initial or is_filter-soiline is initial.
      return.
    endif.

    data(lo_engine) = run_engine( is_filter ).
    data(lt_details) = lo_engine->get_details( is_filter-soiline ).

    loop at lt_details assigning field-symbol(<ls_detail>).
      if ( is_filter-kostl        is not initial and <ls_detail>-kostl        <> is_filter-kostl )
      or ( is_filter-aufnr        is not initial and <ls_detail>-aufnr        <> is_filter-aufnr )
      or ( is_filter-kstar        is not initial and <ls_detail>-kstar        <> is_filter-kstar )
      or ( is_filter-comp_soiline is not initial and <ls_detail>-comp_soiline <> is_filter-comp_soiline ).
        continue.
      endif.

      data(ls_row) = value y0000co_c_soidet(
        soiversion             = is_filter-soivar
        fiscalyear             = is_filter-gjahr
        companycode            = is_filter-bukrs
        valuetype              = is_filter-wrttp
        version                = is_filter-versn
        periodfrom             = is_filter-perv
        periodto               = is_filter-perb
        compareyear            = is_filter-gjahr2
        compareversion         = is_filter-versn2
        comparevaluetype       = is_filter-wrttp2
        soiline                = is_filter-soiline
        costcenter             = <ls_detail>-kostl
        ordernumber            = <ls_detail>-aufnr
        costelement            = <ls_detail>-kstar
        componentline          = <ls_detail>-comp_soiline
        rowtype                = switch #( <ls_detail>-row_type
                                           when 'C' then 'Cost Center'
                                           when 'O' then 'Order'
                                           when 'F' then 'Formula Component' )
        costelementtext        = <ls_detail>-kstar_txt
        componenttext          = <ls_detail>-comp_text
        operator               = <ls_detail>-oper_type
        costcentercategory     = <ls_detail>-kosar
        costcentercategorytext = <ls_detail>-kosar_txt
        functionalarea         = <ls_detail>-fkber
        functionalareatext     = <ls_detail>-fkber_txt
        totalamount            = <ls_detail>-value
        compareamount          = <ls_detail>-value_cmp
        differenceamount       = <ls_detail>-diff_abs
        differencepercent      = <ls_detail>-diff_pct
        specialperiods         = <ls_detail>-special
        currency               = <ls_detail>-waers ).

      do 12 times.
        lv_period3 = sy-index.
        lv_period2 = sy-index.
        assign component |VAL{ lv_period3 }| of structure <ls_detail> to <lv_src>.
        assign component |PERIOD{ lv_period2 }| of structure ls_row to <lv_tgt>.
        if <lv_src> is assigned and <lv_tgt> is assigned.
          <lv_tgt> = <lv_src>.
        endif.
        unassign: <lv_src>, <lv_tgt>.
      enddo.

      append ls_row to rt_detail.
    endloop.

  endmethod.


  method build_context.
*---------------------------------------------------------------------*
* Engine run context from the filter values
*---------------------------------------------------------------------*
* A comparison is requested as soon as one comparison field is filled,
* as IS_COMPARE_REQUESTED in the report.
*---------------------------------------------------------------------*

    rs_context = value #( soivar  = is_filter-soivar
                          bukrs   = is_filter-bukrs
                          gjahr   = is_filter-gjahr
                          versn   = is_filter-versn
                          wrttp   = is_filter-wrttp
                          perv    = is_filter-perv
                          perb    = is_filter-perb
                          compare = xsdbool( is_filter-gjahr2 is not initial
                                          or is_filter-versn2 is not initial
                                          or is_filter-wrttp2 is not initial )
                          gjahr2  = is_filter-gjahr2
                          versn2  = is_filter-versn2
                          wrttp2  = is_filter-wrttp2 ).

  endmethod.


  method read_items.
*---------------------------------------------------------------------*
* Line items behind one breakdown row (entity Y0000CO_C_SOIITM)
*---------------------------------------------------------------------*
* Called when the detail page of a breakdown row follows the
* association _ITEMS: the filter carries all keys of the row. As in
* the report, line items exist for cost center rows only - order and
* formula component rows return nothing. The engine does not run the
* whole statement for this, only its checks (authorization, company
* code, currency, period range). The item keys in the filter are only
* set when one item is read by its key; then only that item returns.
*---------------------------------------------------------------------*

    if is_filter-bukrs is initial or is_filter-gjahr is initial
    or is_filter-kostl is initial or is_filter-kstar is initial.
      return.
    endif.

    data(lo_engine) = new y0000co_cl_soi_engine( ).

    data(lt_items) = lo_engine->get_line_items( is_context = build_context( is_filter )
                                                iv_kostl   = is_filter-kostl
                                                iv_kstar   = is_filter-kstar ).

    data(lv_error) = lo_engine->get_error( ).
    if lv_error is not initial.
      cl_message_helper=>set_msg_vars_for_clike( lv_error ).
      raise exception type y0000co_cx_soi
        message e398(00) with sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    endif.

    loop at lt_items assigning field-symbol(<ls_item>).
      data(lv_data_set) = cond string( when <ls_item>-data_set = 'B' then `Comparison` else `Base` ).

      if ( is_filter-data_set is not initial and lv_data_set      <> is_filter-data_set )
      or ( is_filter-belnr    is not initial and <ls_item>-belnr <> is_filter-belnr )
      or ( is_filter-buzei    is not initial and <ls_item>-buzei <> is_filter-buzei )
      or ( is_filter-perio    is not initial and <ls_item>-perio <> is_filter-perio ).
        continue.
      endif.

      append value y0000co_c_soiitm(
        soiversion       = is_filter-soivar
        fiscalyear       = is_filter-gjahr
        companycode      = is_filter-bukrs
        valuetype        = is_filter-wrttp
        version          = is_filter-versn
        periodfrom       = is_filter-perv
        periodto         = is_filter-perb
        compareyear      = is_filter-gjahr2
        compareversion   = is_filter-versn2
        comparevaluetype = is_filter-wrttp2
        soiline          = is_filter-soiline
        costcenter       = is_filter-kostl
        ordernumber      = is_filter-aufnr
        costelement      = is_filter-kstar
        componentline    = is_filter-comp_soiline
        dataset          = lv_data_set
        documentnumber   = <ls_item>-belnr
        documentitem     = <ls_item>-buzei
        fiscalperiod     = <ls_item>-perio
        postingdate      = <ls_item>-budat
        amount           = <ls_item>-wogbtr
        documenttext     = <ls_item>-bltxt
        username         = <ls_item>-usnam
        documentdate     = <ls_item>-bldat
        entrydate        = <ls_item>-cpudt
        itemfiscalyear   = <ls_item>-gjahr
        itemversion      = <ls_item>-versn
        currency         = <ls_item>-waers ) to rt_item.
    endloop.

  endmethod.


  method respond.
*---------------------------------------------------------------------*
* Sort, page and return a result table (either entity)
*---------------------------------------------------------------------*
* Without a requested sort the table keeps the engine order (outline
* order for SOI lines). Sort element names are the entity element
* names and match the component names of the row structure, so they
* drive a dynamic SORT. Paging ($skip / $top) is applied in memory;
* PAGE_SIZE_UNLIMITED means no $top was sent. The count is the number
* of rows before paging.
*---------------------------------------------------------------------*

    data lr_page type ref to data.

    field-symbols <lt_page> type standard table.

    data(lt_sort_elements) = io_request->get_sort_elements( ).
    if lt_sort_elements is not initial.
      data(lt_sort_order) = value abap_sortorder_tab(
        for ls_sort in lt_sort_elements
        ( name       = to_upper( ls_sort-element_name )
          descending = ls_sort-descending ) ).
      sort ct_result by (lt_sort_order).
    endif.

    data(lv_offset)    = conv i( io_request->get_paging( )->get_offset( ) ).
    data(lv_page_size) = conv i( io_request->get_paging( )->get_page_size( ) ).

    create data lr_page like ct_result.
    assign lr_page->* to <lt_page>.

    data(lv_from) = lv_offset + 1.
    data(lv_to)   = cond i( when lv_page_size = if_rap_query_paging=>page_size_unlimited
                            then lines( ct_result )
                            else lv_offset + lv_page_size ).

    loop at ct_result assigning field-symbol(<ls_row>) from lv_from to lv_to.
      append <ls_row> to <lt_page>.
    endloop.

    if io_request->is_data_requested( ) = abap_true.
      io_response->set_data( <lt_page> ).
    endif.

    if io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( ct_result ) ).
    endif.

  endmethod.

endclass.
